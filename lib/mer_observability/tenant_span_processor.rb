require 'opentelemetry-sdk'

module MerObservability
  # Injects the current Apartment tenant as a span attribute on every span start.
  class TenantSpanProcessor < OpenTelemetry::SDK::Trace::SpanProcessor
    TENANT_ATTRIBUTE = 'tenant'.freeze

    def on_start(span, _parent_context)
      return unless defined?(Apartment::Tenant)

      tenant = Apartment::Tenant.current
      span.set_attribute(TENANT_ATTRIBUTE, tenant) unless tenant.to_s.empty?
    rescue StandardError
      # never let observability break the application
    end
  end
end
