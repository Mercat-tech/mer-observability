require 'spec_helper'

RSpec.describe MerObservability do
  describe '.config' do
    it 'returns a Configuration instance' do
      expect(described_class.config).to be_a(MerObservability::Configuration)
    end

    it 'memoizes the same instance across calls' do
      first = described_class.config
      second = described_class.config
      expect(second).to equal(first)
    end
  end

  describe '.configure' do
    it 'yields the singleton config so callers can mutate it' do
      described_class.configure do |c|
        c.capture_tenant = false
        c.sampler_ratio  = 0.25
      end
      expect(described_class.config.capture_tenant).to eq(false)
      expect(described_class.config.sampler_ratio).to eq(0.25)
    end
  end

  describe '.reset!' do
    it 'forces a fresh Configuration on next call' do
      first = described_class.config
      described_class.reset!
      second = described_class.config
      expect(second).not_to equal(first)
    end
  end
end
