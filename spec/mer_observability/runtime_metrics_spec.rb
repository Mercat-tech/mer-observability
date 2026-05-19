require 'spec_helper'

RSpec.describe MerObservability::RuntimeMetrics do
  describe '.install!' do
    let(:meter) { instance_double('OpenTelemetry::Metrics::Meter') }

    before do
      provider = double('MeterProvider', meter: meter)
      allow(OpenTelemetry).to receive(:meter_provider).and_return(provider)
      allow(meter).to receive(:create_observable_gauge)
    end

    it 'creates the expected gauges' do
      expected_names = %w[
        ruby.gc.count
        ruby.gc.major_count
        ruby.gc.minor_count
        ruby.gc.heap_live_slots
        ruby.gc.heap_free_slots
        ruby.threads.count
        ruby.process.rss_bytes
      ]
      expected_names.each do |name|
        expect(meter).to receive(:create_observable_gauge).with(name, hash_including(:callback, :unit, :description))
      end
      described_class.install!
    end

    it 'returns true on success' do
      expect(described_class.install!).to eq(true)
    end

    it 'rescues and returns false if meter setup raises' do
      allow(OpenTelemetry).to receive(:meter_provider).and_raise(StandardError, 'no meter')
      expect(described_class.install!).to eq(false)
    end
  end
end
