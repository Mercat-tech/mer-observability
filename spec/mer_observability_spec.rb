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

  describe '.log_context' do
    after { described_class.reset_log_context! }

    it 'returns an empty hash by default' do
      described_class.reset_log_context!
      expect(described_class.log_context).to eq({})
    end

    it 'persists fields set on it within the thread' do
      described_class.log_context[:origin_request_id] = 'req-1'
      expect(described_class.log_context[:origin_request_id]).to eq('req-1')
    end

    it 'is cleared by reset_log_context!' do
      described_class.log_context[:foo] = 'bar'
      described_class.reset_log_context!
      expect(described_class.log_context).to eq({})
    end

    it 'is isolated per thread' do
      described_class.log_context[:foo] = 'main'
      other = Thread.new { described_class.log_context.dup }.value
      expect(other).to eq({})
    end
  end
end
