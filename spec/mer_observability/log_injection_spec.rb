require 'spec_helper'
require 'logger'

RSpec.describe MerObservability::LogInjection do
  let(:io)     { StringIO.new }
  let(:logger) { Logger.new(io) }

  def stub_active_span(trace_id: 'a' * 32, span_id: 'b' * 16, valid: true)
    ctx  = double('SpanContext', valid?: valid, hex_trace_id: trace_id, hex_span_id: span_id)
    span = double('Span', context: ctx)
    allow(OpenTelemetry::Trace).to receive(:current_span).and_return(span)
  end

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
      stub_active_span

      logger.info('hello world')
      expect(io.string).to include("trace_id=#{'a' * 32}")
      expect(io.string).to include("span_id=#{'b' * 16}")
      expect(io.string).to include('hello world')
    end

    it 'skips prefix when trace_id is the invalid all-zero id' do
      described_class.install!(logger)
      stub_active_span(trace_id: '0' * 32, span_id: '0' * 16)

      logger.info('hello world')
      expect(io.string).not_to include('trace_id=')
    end
  end

  context 'with an ActiveSupport::TaggedLogging logger' do
    require 'active_support'
    require 'active_support/tagged_logging'

    let(:underlying) { Logger.new(io) }
    let(:logger)     { ActiveSupport::TaggedLogging.new(underlying) }

    it 'preserves #tagged after install! (regression: NoMethodError on Proc#tagged)' do
      described_class.install!(logger)
      expect { logger.tagged('req-123') { logger.info('hello') } }.not_to raise_error
      expect(io.string).to include('[req-123] hello')
    end

    it 'emits trace_id, span_id, tags, and message in order when a span is active' do
      described_class.install!(logger)
      stub_active_span

      logger.tagged('req-123') { logger.info('hello') }
      expect(io.string).to match(/trace_id=#{'a' * 32} span_id=#{'b' * 16} \[req-123\] hello/)
    end

    it 'is idempotent — calling install! twice does not double-prefix' do
      described_class.install!(logger)
      described_class.install!(logger)
      stub_active_span

      logger.tagged('x') { logger.info('y') }
      expect(io.string.scan('trace_id=').size).to eq(1)
    end

    it 'keeps the formatter responding to TaggedLogging methods' do
      described_class.install!(logger)
      expect(logger.formatter).to respond_to(:tagged, :push_tags, :pop_tags, :clear_tags!, :current_tags)
    end
  end
end
