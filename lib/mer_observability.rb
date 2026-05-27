require 'mer_observability/version'
require 'mer_observability/configuration'
require 'mer_observability/tenant_span_processor'
require 'mer_observability/log_injection'
require 'mer_observability/json_formatter'
require 'mer_observability/text_formatter'
require 'mer_observability/formatter'
require 'mer_observability/runtime_metrics'
require 'mer_observability/setup'
require 'mer_observability/railtie' if defined?(Rails)

module MerObservability
  LOG_CONTEXT_KEY = :mer_observability_log_context

  class << self
    def configure
      yield config
    end

    def config
      @config ||= Configuration.new
    end

    def reset!
      @config = nil
    end

    # Per-thread bag of fields that the JsonFormatter merges into every log
    # line emitted on the current thread. Generic extension point: the gem
    # does not define what goes here — apps populate it (e.g. a Sidekiq server
    # middleware setting an origin request id). No-op when left empty.
    def log_context
      Thread.current[LOG_CONTEXT_KEY] ||= {}
    end

    def reset_log_context!
      Thread.current[LOG_CONTEXT_KEY] = {}
    end
  end
end
