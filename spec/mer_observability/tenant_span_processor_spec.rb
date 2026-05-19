require 'spec_helper'

RSpec.describe MerObservability::TenantSpanProcessor do
  let(:span)    { instance_double('OpenTelemetry::Trace::Span') }
  let(:context) { double('OpenTelemetry::Context') }

  subject(:processor) { described_class.new }

  describe '#on_start' do
    context 'when Apartment is not loaded' do
      it 'is a no-op' do
        hide_const('Apartment') if defined?(Apartment)
        expect(span).not_to receive(:set_attribute)
        processor.on_start(span, context)
      end
    end

    context 'when Apartment is loaded with a current tenant' do
      before do
        apartment_module = Module.new
        tenant = Module.new do
          def self.current = 'pizzeria-juan'
        end
        apartment_module.const_set(:Tenant, tenant)
        stub_const('Apartment', apartment_module)
        stub_const('Apartment::Tenant', tenant)
      end

      it 'sets the tenant attribute on the span' do
        expect(span).to receive(:set_attribute).with('tenant', 'pizzeria-juan')
        processor.on_start(span, context)
      end
    end

    context 'when Apartment.current returns blank' do
      before do
        apartment_module = Module.new
        tenant = Module.new do
          def self.current = ''
        end
        apartment_module.const_set(:Tenant, tenant)
        stub_const('Apartment', apartment_module)
        stub_const('Apartment::Tenant', tenant)
      end

      it 'does not set the attribute' do
        # Some Ruby strings respond to present? when ActiveSupport is loaded.
        # The processor calls .present?, which on a plain '' returns nil/false.
        allow(''.dup).to receive(:present?).and_return(false) if ''.respond_to?(:present?)
        expect(span).not_to receive(:set_attribute)
        processor.on_start(span, context)
      end
    end

    context 'when Apartment raises' do
      before do
        apartment_module = Module.new
        tenant = Module.new do
          def self.current = raise('apartment is angry')
        end
        apartment_module.const_set(:Tenant, tenant)
        stub_const('Apartment', apartment_module)
        stub_const('Apartment::Tenant', tenant)
      end

      it 'rescues and never propagates the error' do
        expect { processor.on_start(span, context) }.not_to raise_error
      end
    end
  end
end
