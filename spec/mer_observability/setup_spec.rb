require 'spec_helper'

RSpec.describe MerObservability::Setup do
  let(:config) { MerObservability::Configuration.new }

  describe '.call' do
    it 'returns early when config is disabled (no endpoint)' do
      expect(OpenTelemetry::SDK).not_to receive(:configure)
      described_class.call(config)
    end

    it 'never raises if any setup step fails' do
      allow(config).to receive(:enabled).and_return(true)
      allow(described_class).to receive(:build_trace_exporter).and_raise(StandardError, 'boom')
      expect { described_class.call(config) }.not_to raise_error
    end

    # The OTLP metrics exporter reads its temporality preference from this ENV
    # var at instantiation time. Setup.call must propagate the configured value
    # to the env BEFORE the exporter is built.
    describe 'temporality preference propagation' do
      let(:env_key) { 'OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE' }

      around do |example|
        prev = ENV.fetch(env_key, nil)
        ENV.delete(env_key)
        example.run
      ensure
        prev.nil? ? ENV.delete(env_key) : ENV[env_key] = prev
      end

      it 'sets the env var from the config when enabled' do
        allow(config).to receive(:enabled).and_return(true)
        allow(config).to receive(:metrics_temporality_preference).and_return('delta')
        # Short-circuit the rest of setup so we don't actually configure the SDK.
        allow(described_class).to receive(:build_trace_exporter).and_raise(StandardError, 'stop')

        described_class.call(config)

        expect(ENV.fetch(env_key, nil)).to eq('delta')
      end

      it 'leaves the env var untouched when setup is disabled' do
        described_class.call(config)
        expect(ENV.fetch(env_key, nil)).to be_nil
      end
    end
  end

  describe '.build_sampler' do
    it 'returns nil when ratio >= 1.0 (always-on)' do
      allow(config).to receive(:sampler_ratio).and_return(1.0)
      expect(described_class.build_sampler(config)).to be_nil
    end

    it 'returns a parent_based sampler for ratio < 1.0' do
      allow(config).to receive(:sampler_ratio).and_return(0.1)
      sampler = described_class.build_sampler(config)
      expect(sampler).not_to be_nil
    end

    it 'clamps negative ratios to 0.0' do
      allow(config).to receive(:sampler_ratio).and_return(-0.5)
      expect { described_class.build_sampler(config) }.not_to raise_error
    end
  end

  describe '.build_trace_exporter' do
    it 'returns the HTTP/protobuf exporter' do
      allow(config).to receive(:endpoint).and_return('http://collector:4318')
      stub_const('OpenTelemetry::Exporter::OTLP::Exporter', Class.new do
        def self.new(**) = :http_exporter
      end)
      expect(described_class.build_trace_exporter(config)).to eq(:http_exporter)
    end
  end

  describe '.trace_endpoint' do
    it 'appends /v1/traces to the base endpoint' do
      allow(config).to receive(:endpoint).and_return('http://collector:4318')
      expect(described_class.trace_endpoint(config)).to eq('http://collector:4318/v1/traces')
    end

    it 'strips trailing slash before appending' do
      allow(config).to receive(:endpoint).and_return('http://collector:4318/')
      expect(described_class.trace_endpoint(config)).to eq('http://collector:4318/v1/traces')
    end
  end

  describe '.metrics_endpoint' do
    it 'appends /v1/metrics to the base endpoint' do
      allow(config).to receive(:endpoint).and_return('http://collector:4318')
      expect(described_class.metrics_endpoint(config)).to eq('http://collector:4318/v1/metrics')
    end

    it 'strips trailing slash before appending' do
      allow(config).to receive(:endpoint).and_return('http://collector:4318/')
      expect(described_class.metrics_endpoint(config)).to eq('http://collector:4318/v1/metrics')
    end
  end
end
