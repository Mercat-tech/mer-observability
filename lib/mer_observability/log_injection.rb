require 'opentelemetry-sdk'

module MerObservability
  # Prepends `trace_id=<id> span_id=<id>` to every line emitted by Rails.logger
  # so each log can be correlated to its trace in your tracing backend UI.
  #
  # Implementation note: we `prepend` a module into the existing formatter's
  # singleton class instead of replacing the formatter. This preserves the
  # object's identity, which matters because ActiveSupport::TaggedLogging
  # extends `ActiveSupport::TaggedLogging::Formatter` directly onto the
  # formatter instance at boot. Replacing the formatter would lose `#tagged`,
  # `#push_tags`, `#pop_tags`, etc. The MRO becomes:
  #
  #   TracePrefix → TaggedLogging::Formatter → Logger::Formatter
  #
  # so calling `super` in TracePrefix#call returns the line already formatted
  # with tags, and we just prepend the OTel ids.
  module LogInjection
    INVALID_HEX_ID = '0' * 32

    module TracePrefix
      def call(severity, time, progname, msg)
        formatted = super
        prefix = MerObservability::LogInjection.trace_prefix
        prefix.empty? ? formatted : MerObservability::LogInjection.prepend_prefix(formatted, prefix)
      end
    end

    def self.install!(logger = nil)
      logger ||= (defined?(Rails) ? Rails.logger : nil)
      return unless logger
      return if logger.instance_variable_get(:@mer_observability_installed)

      target = resolve_target(logger)
      target.singleton_class.prepend(TracePrefix) unless target.singleton_class.include?(TracePrefix)
      logger.instance_variable_set(:@mer_observability_installed, true)
    end

    def self.resolve_target(logger)
      formatter = logger.formatter ||= ::Logger::Formatter.new
      formatter.is_a?(Proc) ? wrap_proc_formatter(logger, formatter) : formatter
    end

    # Wrap a Proc formatter in a minimal class so `singleton_class.prepend` can apply.
    # Rare path — Rails uses Logger::Formatter (a class instance) by default.
    def self.wrap_proc_formatter(logger, proc_formatter)
      shim = Class.new do
        define_method(:call) { |sev, t, prog, msg| proc_formatter.call(sev, t, prog, msg) }
      end.new
      logger.formatter = shim
      shim
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
