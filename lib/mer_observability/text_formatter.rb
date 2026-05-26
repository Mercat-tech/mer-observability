require 'opentelemetry-sdk'

module MerObservability
  # Emits log lines in the legacy text format used in development. Equivalent
  # to the default Ruby Logger output with a prefix that exposes the service
  # name, trace_id and span_id at the start of every line:
  #
  #   service=mer-core trace_id=abc... span_id=def... I, [TIME #PID]  INFO -- progname: [tag] message
  #
  # This formatter is intentionally human-readable in terminals. For
  # stage/production use `JsonFormatter` instead via `Formatter.build`.
  class TextFormatter < ::Logger::Formatter
    INVALID_HEX_ID = ('0' * 32).freeze

    def call(severity, time, progname, msg)
      formatted = super
      prefix = build_prefix
      prefix.empty? ? formatted : "#{prefix}#{formatted}"
    end

    private

    def build_prefix
      parts = []
      service = MerObservability.config.service_name.to_s
      parts << "service=#{service}" unless service.empty?

      span = OpenTelemetry::Trace.current_span
      if span
        ctx = span.context
        if ctx&.valid?
          trace_id = ctx.hex_trace_id
          if trace_id && trace_id != INVALID_HEX_ID
            parts << "trace_id=#{trace_id}"
            parts << "span_id=#{ctx.hex_span_id}"
          end
        end
      end

      parts.any? ? "#{parts.join(' ')} " : ''
    rescue StandardError
      ''
    end
  end
end
