require 'json'
require 'time'
require 'opentelemetry-sdk'

module MerObservability
  # Emits one JSON object per log line. Designed for stage/production where
  # logs are shipped to an OTel-compatible aggregator (SigNoz).
  #
  # Behavior:
  #
  # * When `msg` is a Hash, all keys are merged into the output JSON
  # * When `msg` is a String, it becomes the "message" field
  # * When `msg` is an Exception, its message + class name are extracted
  # * Auto-populates trace_id/span_id from the current OTel span (when present)
  # * Auto-populates tenant from Apartment::Tenant.current (when defined)
  # * Auto-populates request_id from ActiveSupport::TaggedLogging tags (first tag)
  # * Auto-parses `KEY: value` tags into fields (e.g., "TENANT: x" → tenant: "x")
  # * Accepts a `defaults` hash for per-instance presets (e.g., component: 'sqs')
  #
  # The OTel Collector's `transform/json_logs` processor parses the resulting
  # JSON and promotes service/trace_id/span_id/level/message to OTel-standard
  # positions on the LogRecord. The remaining fields land in log attributes
  # automatically (no schema change required in the collector).
  class JsonFormatter < ::Logger::Formatter
    INVALID_HEX_ID = ('0' * 32).freeze
    TAG_KV_PATTERN = /\A([A-Z][A-Z_]*):\s*(.*)\z/

    def initialize(defaults: {})
      super()
      @defaults = defaults || {}
    end

    def call(severity, time, progname, msg)
      payload = base_payload(severity, time)
      payload.merge!(@defaults)
      payload.merge!(otel_context)
      payload.merge!(tenant_context)
      payload.merge!(tagged_context(msg))
      payload[:progname] = progname.to_s unless progname.to_s.empty?
      payload.merge!(msg_payload(msg))
      "#{::JSON.generate(payload)}\n"
    rescue StandardError => e
      # Never let logging break the application. Fall back to a minimal JSON line.
      fallback = { timestamp: Time.now.utc.iso8601(6), level: severity.to_s, message: msg.to_s, formatter_error: e.message }
      "#{::JSON.generate(fallback)}\n"
    end

    private

    def base_payload(severity, time)
      {
        timestamp: time.utc.iso8601(6),
        level: severity.to_s,
        service: MerObservability.config.service_name.to_s,
        pid: $PID
      }
    end

    def otel_context
      span = OpenTelemetry::Trace.current_span
      return {} unless span

      ctx = span.context
      return {} unless ctx&.valid?

      trace_id = ctx.hex_trace_id
      return {} if trace_id.nil? || trace_id == INVALID_HEX_ID

      { trace_id: trace_id, span_id: ctx.hex_span_id }
    rescue StandardError
      {}
    end

    def tenant_context
      return {} unless defined?(Apartment::Tenant)

      tenant = Apartment::Tenant.current
      tenant.to_s.empty? ? {} : { tenant: tenant.to_s }
    rescue StandardError
      {}
    end

    # Pulls fields from ActiveSupport::TaggedLogging current_tags. The
    # underlying TaggedLogging::Formatter already prepended the tags as text
    # to `msg` by the time we run; we read the original tag array from the
    # thread-local that TaggedLogging populates and translate to fields.
    def tagged_context(_msg)
      tags = Thread.current[:activesupport_tagged_logging_tags]
      return {} if tags.nil? || tags.empty?

      fields = {}
      tags.each_with_index do |tag, idx|
        match = TAG_KV_PATTERN.match(tag.to_s)
        if match
          fields[match[1].downcase.to_sym] = match[2]
        elsif idx.zero?
          fields[:request_id] = tag.to_s
        end
      end
      fields
    rescue StandardError
      {}
    end

    def msg_payload(msg)
      case msg
      when Hash
        # If the hash already has a :message key it stays; otherwise the whole
        # hash becomes the log fields (use case: structured event logs).
        msg.transform_keys(&:to_sym)
      when Exception
        { message: msg.message, exception_class: msg.class.name }
      else
        clean = strip_tag_prefix(msg.to_s)
        { message: clean }
      end
    end

    # ActiveSupport::TaggedLogging::Formatter prepends `[tag] [tag] ` to msg
    # before reaching us. We strip that text so the JSON `message` field
    # contains only the actual log message (tags are extracted to fields by
    # `tagged_context`).
    def strip_tag_prefix(str)
      tags = Thread.current[:activesupport_tagged_logging_tags]
      return str if tags.nil? || tags.empty?

      prefix = tags.map { |t| "[#{t}] " }.join
      str.start_with?(prefix) ? str[prefix.length..] : str
    end
  end
end
