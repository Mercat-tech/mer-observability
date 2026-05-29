module MerObservability
  class Configuration
    attr_accessor :service_name,
                  :service_version,
                  :environment,
                  :endpoint,
                  :enabled,
                  :capture_tenant,
                  :sampler_ratio,
                  :log_injection,
                  :log_format,
                  :runtime_metrics_enabled,
                  :runtime_metrics_interval,
                  :metrics_temporality_preference

    def initialize
      @service_name                   = ENV['OTEL_SERVICE_NAME'] || default_service_name
      @service_version                = default_service_version
      @environment                    = ENV['RENV'] || ENV['RAILS_ENV'] || 'development'
      @endpoint                       = ENV.fetch('OTEL_EXPORTER_OTLP_ENDPOINT', nil)
      @enabled                        = !@endpoint.nil? && !@endpoint.empty?
      @capture_tenant                 = true
      @sampler_ratio                  = ENV.fetch('OTEL_TRACES_SAMPLER_ARG', '1.0').to_f
      @log_injection                  = ENV.fetch('OTEL_LOG_INJECTION', 'true') == 'true'
      @log_format                     = ENV['MER_LOG_FORMAT'] || default_log_format
      @runtime_metrics_enabled        = ENV.fetch('OTEL_RUBY_RUNTIME_METRICS', 'true') == 'true'
      @runtime_metrics_interval       = ENV.fetch('OTEL_RUBY_RUNTIME_METRICS_INTERVAL', '30').to_i
      # delta: synchronous counters/histograms only emit when there's activity (vs cumulative,
      # which re-exports every active series each interval). On per-sample-priced backends
      # (SigNoz Cloud) this is what bounds ingestion cost to actual events.
      @metrics_temporality_preference = ENV.fetch('OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE', 'delta')
    end

    private

    def default_service_name
      return 'unknown-service' unless defined?(Rails)

      base = Rails.application.class.module_parent_name.underscore.dasherize
      defined?(Sidekiq) && Sidekiq.server? ? "#{base}-sidekiq" : base
    rescue StandardError
      'unknown-service'
    end

    def default_service_version
      version_from_env || version_from_rails_files || 'unknown'
    rescue StandardError
      'unknown'
    end

    def default_log_format
      stage_or_prod?(@environment) ? 'json' : 'text'
    end

    def stage_or_prod?(env)
      %w[production stage staging prod].include?(env.to_s.downcase)
    end

    def version_from_env
      v = ENV.fetch('APP_VERSION', nil)
      return v if v && !v.empty?

      sha = ENV.fetch('GIT_SHA', nil)
      sha if sha && !sha.empty?
    end

    def version_from_rails_files
      return unless defined?(Rails) && Rails.respond_to?(:root) && Rails.root

      revision = Rails.root.join('REVISION')
      return revision.read.strip if revision.exist?

      head = Rails.root.join('.git', 'HEAD')
      head.read.strip[0, 12] if head.exist?
    end
  end
end
