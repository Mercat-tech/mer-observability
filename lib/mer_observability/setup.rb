require 'opentelemetry-sdk'
require 'opentelemetry-exporter-otlp'
require 'opentelemetry-metrics-sdk'
require 'opentelemetry/instrumentation/rack'
require 'opentelemetry/instrumentation/action_pack'
require 'opentelemetry/instrumentation/action_view'
require 'opentelemetry/instrumentation/active_support'
require 'opentelemetry/instrumentation/rails'
require 'opentelemetry/instrumentation/active_record'
require 'opentelemetry/instrumentation/sidekiq'
require 'opentelemetry/instrumentation/redis'
require 'opentelemetry/instrumentation/net/http'
require 'opentelemetry/instrumentation/faraday'
require 'opentelemetry/instrumentation/http'

module MerObservability
  module Setup
    def self.call(config)
      return unless config.enabled

      # Applied via ENV because the OTLP metrics exporter reads its temporality
      # preference at instantiation time. Setting it here ensures the exporter
      # built below picks up the configured value regardless of load order.
      ENV['OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE'] = config.metrics_temporality_preference

      span_processor = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(build_trace_exporter(config))
      metric_reader  = build_metric_reader(config) if config.runtime_metrics_enabled

      configure_sdk(config, span_processor, build_sampler(config), metric_reader)

      RuntimeMetrics.install! if config.runtime_metrics_enabled
      install_sidekiq_logger!(config)
    rescue StandardError => e
      warn "[MerObservability] Setup failed: #{e.message} — tracing disabled."
    end

    # Patches Sidekiq.logger.formatter with the gem's Formatter factory result
    # so that worker logs share the same format as Rails.logger. Only runs in
    # the Sidekiq server process (Sidekiq.configure_server is a no-op in web
    # processes). Idempotent and safe when Sidekiq is not loaded.
    def self.install_sidekiq_logger!(_config)
      return unless defined?(Sidekiq)
      return unless Sidekiq.respond_to?(:configure_server)

      Sidekiq.configure_server do |sk_config|
        sk_config.on(:startup) do
          Sidekiq.logger.formatter = Formatter.build if Sidekiq.logger
        end
      end
    rescue StandardError => e
      warn "[MerObservability] Sidekiq logger setup failed: #{e.message}"
    end

    def self.configure_sdk(config, span_processor, sampler, metric_reader)
      OpenTelemetry::SDK.configure do |otel|
        otel.resource = OpenTelemetry::SDK::Resources::Resource.create(
          'service.name' => config.service_name,
          'service.version' => config.service_version,
          'deployment.environment' => config.environment
        )
        otel.add_span_processor(span_processor)
        otel.add_span_processor(TenantSpanProcessor.new) if config.capture_tenant
        otel.tracer_provider.sampler = sampler if sampler
        otel.add_metric_reader(metric_reader) if metric_reader

        otel.use 'OpenTelemetry::Instrumentation::Rack'
        otel.use 'OpenTelemetry::Instrumentation::ActionPack'
        otel.use 'OpenTelemetry::Instrumentation::ActionView'
        otel.use 'OpenTelemetry::Instrumentation::ActiveSupport'
        otel.use 'OpenTelemetry::Instrumentation::Rails'
        otel.use 'OpenTelemetry::Instrumentation::ActiveRecord'
        otel.use 'OpenTelemetry::Instrumentation::Sidekiq'
        otel.use 'OpenTelemetry::Instrumentation::Redis'
        otel.use 'OpenTelemetry::Instrumentation::Net::HTTP'
        otel.use 'OpenTelemetry::Instrumentation::Faraday'
        otel.use 'OpenTelemetry::Instrumentation::HTTP'
      end
    end

    def self.build_trace_exporter(config)
      OpenTelemetry::Exporter::OTLP::Exporter.new(endpoint: trace_endpoint(config))
    end

    def self.build_metric_exporter(config)
      require 'opentelemetry-exporter-otlp-metrics'
      OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter.new(endpoint: metrics_endpoint(config))
    end

    def self.trace_endpoint(config)
      "#{config.endpoint.to_s.chomp('/')}/v1/traces"
    end

    def self.metrics_endpoint(config)
      "#{config.endpoint.to_s.chomp('/')}/v1/metrics"
    end

    def self.build_metric_reader(config)
      OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
        exporter: build_metric_exporter(config),
        export_interval_millis: config.runtime_metrics_interval * 1000
      )
    end

    def self.build_sampler(config)
      ratio = config.sampler_ratio
      return nil if ratio >= 1.0

      ratio = 0.0 if ratio.negative?
      OpenTelemetry::SDK::Trace::Samplers.parent_based(
        root: OpenTelemetry::SDK::Trace::Samplers.trace_id_ratio_based(ratio)
      )
    end
  end
end
