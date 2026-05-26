require 'spec_helper'

RSpec.describe MerObservability::Formatter do
  describe '.build' do
    it 'returns a JsonFormatter when log_format is "json"' do
      MerObservability.configure { |c| c.log_format = 'json' }
      expect(described_class.build).to be_a(MerObservability::JsonFormatter)
    end

    it 'returns a TextFormatter when log_format is "text"' do
      MerObservability.configure { |c| c.log_format = 'text' }
      expect(described_class.build).to be_a(MerObservability::TextFormatter)
    end

    it 'falls back to TextFormatter for any unknown log_format value' do
      MerObservability.configure { |c| c.log_format = 'xml' }
      expect(described_class.build).to be_a(MerObservability::TextFormatter)
    end

    it 'normalizes log_format case-insensitively' do
      MerObservability.configure { |c| c.log_format = 'JSON' }
      expect(described_class.build).to be_a(MerObservability::JsonFormatter)
    end

    it 'passes defaults through to the JsonFormatter' do
      MerObservability.configure { |c| c.log_format = 'json' }
      json_formatter = instance_double(MerObservability::JsonFormatter)
      expect(MerObservability::JsonFormatter).to receive(:new).with(defaults: { component: 'sqs' }).and_return(json_formatter)
      described_class.build(defaults: { component: 'sqs' })
    end
  end
end
