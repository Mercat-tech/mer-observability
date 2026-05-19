require 'spec_helper'
require 'logger'

RSpec.describe MerObservability::LogInjection do
  let(:io)     { StringIO.new }
  let(:logger) { Logger.new(io) }

  describe '.install!' do
    it 'is idempotent — installing twice does not double-wrap' do
      described_class.install!(logger)
      first = logger.formatter
      described_class.install!(logger)
      second = logger.formatter
      expect(second).to equal(first)
    end

    it 'returns nothing when given a nil logger' do
      expect { described_class.install!(nil) }.not_to raise_error
    end

    it 'leaves output unchanged when no span is active' do
      described_class.install!(logger)
      allow(OpenTelemetry::Trace).to receive(:current_span).and_return(nil)
      logger.info('hello world')
      expect(io.string).to include('hello world')
      expect(io.string).not_to include('trace_id=')
    end

    it 'prepends trace_id and span_id when an active valid span exists' do
      described_class.install!(logger)

      ctx  = double('SpanContext',
                    valid?: true,
                    hex_trace_id: 'a' * 32,
                    hex_span_id: 'b' * 16)
      span = double('Span', context: ctx)
      allow(OpenTelemetry::Trace).to receive(:current_span).and_return(span)

      logger.info('hello world')
      expect(io.string).to include("trace_id=#{'a' * 32}")
      expect(io.string).to include("span_id=#{'b' * 16}")
      expect(io.string).to include('hello world')
    end

    it 'skips prefix when trace_id is the invalid all-zero id' do
      described_class.install!(logger)

      ctx  = double('SpanContext',
                    valid?: true,
                    hex_trace_id: '0' * 32,
                    hex_span_id: '0' * 16)
      span = double('Span', context: ctx)
      allow(OpenTelemetry::Trace).to receive(:current_span).and_return(span)

      logger.info('hello world')
      expect(io.string).not_to include('trace_id=')
    end
  end
end
