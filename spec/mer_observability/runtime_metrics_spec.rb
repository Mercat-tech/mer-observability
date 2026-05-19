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

    # Regression: opentelemetry-metrics-sdk 0.13.x invokes the callback with
    # zero arguments and uses the return value as the observation. Earlier
    # callbacks took `(observer)` and called `observer.observe(x)`, which
    # produced `ArgumentError: wrong number of arguments (given 0, expected 1)`
    # at every export cycle. This spec exercises the callback bodies directly.
    it 'registers callbacks that take zero args and return a Numeric (or nil)' do
      captured = []
      allow(meter).to receive(:create_observable_gauge) do |_name, **kwargs|
        captured << kwargs[:callback]
      end

      described_class.install!

      expect(captured).not_to be_empty
      captured.each do |cb|
        expect(cb.arity).to be <= 0
        result = cb.call
        expect(result).to be_a(Numeric).or be_nil
      end
    end
  end
end
