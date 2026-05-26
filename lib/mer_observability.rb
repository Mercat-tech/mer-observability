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
  end
end
