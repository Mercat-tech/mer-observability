require 'spec_helper'
require 'logger'

RSpec.describe MerObservability::TextFormatter do
  let(:formatter) { described_class.new }
  let(:time)      { Time.utc(2026, 6, 1, 10, 23, 45) }

  def stub_active_span(trace_id: 'a' * 32, span_id: 'b' * 16, valid: true)
    ctx  = double('SpanContext', valid?: valid, hex_trace_id: trace_id, hex_span_id: span_id)
    span = double('Span', context: ctx)
    allow(OpenTelemetry::Trace).to receive(:current_span).and_return(span)
  end

  before do
    allow(OpenTelemetry::Trace).to receive(:current_span).and_return(nil)
  end

  describe '#call' do
    it 'falls back to the Logger::Formatter base output when no context exists' do
      MerObservability.configure { |c| c.service_name = '' }
      output = formatter.call('INFO', time, nil, 'hello')
      expect(output).to include('INFO')
      expect(output).to include('hello')
    end

    it 'prepends service=<name> when service_name is configured' do
      MerObservability.configure { |c| c.service_name = 'mer-core' }
      output = formatter.call('INFO', time, nil, 'hello')
      expect(output).to start_with('service=mer-core ')
    end

    it 'prepends trace_id and span_id when an active span exists' do
      MerObservability.configure { |c| c.service_name = 'mer-core' }
      stub_active_span

      output = formatter.call('INFO', time, nil, 'hello')
      expect(output).to include("trace_id=#{'a' * 32}")
      expect(output).to include("span_id=#{'b' * 16}")
    end

    it 'orders prefix as service then trace_id then span_id when both are present' do
      MerObservability.configure { |c| c.service_name = 'mer-core' }
      stub_active_span

      output = formatter.call('INFO', time, nil, 'hello')
      expect(output).to match(/\Aservice=mer-core trace_id=#{'a' * 32} span_id=#{'b' * 16} /)
    end

    it 'skips trace_id when it is the invalid all-zero id' do
      MerObservability.configure { |c| c.service_name = 'mer-core' }
      stub_active_span(trace_id: '0' * 32, span_id: '0' * 16)

      output = formatter.call('INFO', time, nil, 'hello')
      expect(output).to start_with('service=mer-core ')
      expect(output).not_to include('trace_id=')
    end

    it 'never raises if OpenTelemetry crashes' do
      allow(OpenTelemetry::Trace).to receive(:current_span).and_raise(StandardError, 'boom')
      expect { formatter.call('INFO', time, nil, 'hello') }.not_to raise_error
    end
  end
end
