require 'opentelemetry-sdk'

module MerObservability
  # Wraps the existing Rails.logger formatter so every line is prepended with
  # `trace_id=<id> span_id=<id>` extracted from the currently active OTel span.
  # Allows clicking from a log line to its trace in your tracing backend UI.
  module LogInjection
    INVALID_HEX_ID = '0' * 32

    def self.install!(logger = nil)
      logger ||= (defined?(Rails) ? Rails.logger : nil)
      return unless logger
      return if logger.instance_variable_get(:@mer_observability_installed)

      original_formatter = logger.formatter || Logger::Formatter.new
      logger.formatter = build_formatter(original_formatter)
      logger.instance_variable_set(:@mer_observability_installed, true)
    end

    def self.build_formatter(original)
      proc do |severity, time, progname, msg|
        prefix = trace_prefix
        formatted = original.call(severity, time, progname, msg)
        prefix.empty? ? formatted : prepend_prefix(formatted, prefix)
      end
    end

    def self.trace_prefix
      span = OpenTelemetry::Trace.current_span
      return '' unless span

      ctx = span.context
      return '' unless ctx&.valid?

      trace_id = ctx.hex_trace_id
      return '' if trace_id.nil? || trace_id == INVALID_HEX_ID

      "trace_id=#{trace_id} span_id=#{ctx.hex_span_id} "
    rescue StandardError
      ''
    end

    def self.prepend_prefix(formatted, prefix)
      return "#{prefix}#{formatted}" unless formatted.is_a?(String)
      return "#{prefix}#{formatted}" unless formatted.end_with?("\n")

      formatted.sub(/\A/, prefix)
    end
  end
end
