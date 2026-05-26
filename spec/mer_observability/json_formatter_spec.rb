require 'spec_helper'
require 'json'
require 'logger'

RSpec.describe MerObservability::JsonFormatter do
  let(:formatter) { described_class.new }
  let(:time)      { Time.utc(2026, 6, 1, 10, 23, 45, 123_456) }

  def parse(line)
    JSON.parse(line.chomp)
  end

  def stub_active_span(trace_id: 'a' * 32, span_id: 'b' * 16, valid: true)
    ctx  = double('SpanContext', valid?: valid, hex_trace_id: trace_id, hex_span_id: span_id)
    span = double('Span', context: ctx)
    allow(OpenTelemetry::Trace).to receive(:current_span).and_return(span)
  end

  before do
    allow(OpenTelemetry::Trace).to receive(:current_span).and_return(nil)
    Thread.current[:activesupport_tagged_logging_tags] = nil
  end

  describe '#call' do
    it 'emits a single JSON line terminated with newline' do
      output = formatter.call('INFO', time, nil, 'hello')
      expect(output).to end_with("\n")
      expect(output.count("\n")).to eq(1)
    end

    it 'includes mandatory fields: timestamp, level, service, pid' do
      MerObservability.configure { |c| c.service_name = 'mer-test' }
      parsed = parse(formatter.call('INFO', time, nil, 'hello'))

      expect(parsed['timestamp']).to eq('2026-06-01T10:23:45.123456Z')
      expect(parsed['level']).to eq('INFO')
      expect(parsed['service']).to eq('mer-test')
      expect(parsed['pid']).to eq($PID)
    end

    it 'puts a String msg into the "message" field' do
      parsed = parse(formatter.call('INFO', time, nil, 'order processed'))
      expect(parsed['message']).to eq('order processed')
    end

    it 'merges a Hash msg as top-level fields' do
      parsed = parse(formatter.call('INFO', time, nil, message: 'order processed', order_id: 42, user_id: 999))
      expect(parsed['message']).to eq('order processed')
      expect(parsed['order_id']).to eq(42)
      expect(parsed['user_id']).to eq(999)
    end

    it 'extracts message and class from an Exception' do
      err = StandardError.new('something broke')
      parsed = parse(formatter.call('ERROR', time, nil, err))
      expect(parsed['message']).to eq('something broke')
      expect(parsed['exception_class']).to eq('StandardError')
    end

    it 'includes progname when present' do
      parsed = parse(formatter.call('INFO', time, 'OrdersController', 'render'))
      expect(parsed['progname']).to eq('OrdersController')
    end

    it 'omits progname when nil or empty' do
      parsed = parse(formatter.call('INFO', time, nil, 'hello'))
      expect(parsed).not_to have_key('progname')
    end
  end

  describe 'OTel context auto-population' do
    it 'omits trace_id/span_id when no span is active' do
      parsed = parse(formatter.call('INFO', time, nil, 'hello'))
      expect(parsed).not_to have_key('trace_id')
      expect(parsed).not_to have_key('span_id')
    end

    it 'includes trace_id/span_id when an active valid span exists' do
      stub_active_span
      parsed = parse(formatter.call('INFO', time, nil, 'hello'))
      expect(parsed['trace_id']).to eq('a' * 32)
      expect(parsed['span_id']).to eq('b' * 16)
    end

    it 'skips trace_id when it is the invalid all-zero id' do
      stub_active_span(trace_id: '0' * 32, span_id: '0' * 16)
      parsed = parse(formatter.call('INFO', time, nil, 'hello'))
      expect(parsed).not_to have_key('trace_id')
    end

    it 'never crashes if OpenTelemetry raises unexpectedly' do
      allow(OpenTelemetry::Trace).to receive(:current_span).and_raise(StandardError, 'boom')
      expect { formatter.call('INFO', time, nil, 'hello') }.not_to raise_error
    end
  end

  describe 'tenant auto-population (Apartment)' do
    after { hide_const('Apartment') if defined?(Apartment) }

    it 'omits tenant when Apartment is not defined' do
      hide_const('Apartment') if defined?(Apartment)
      parsed = parse(formatter.call('INFO', time, nil, 'hello'))
      expect(parsed).not_to have_key('tenant')
    end

    it 'reads tenant from Apartment::Tenant.current when present' do
      apartment = Module.new
      tenant_mod = Module.new { def self.current = 'justburger' }
      stub_const('Apartment', apartment)
      stub_const('Apartment::Tenant', tenant_mod)

      parsed = parse(formatter.call('INFO', time, nil, 'hello'))
      expect(parsed['tenant']).to eq('justburger')
    end

    it 'omits tenant when Apartment::Tenant.current is empty' do
      apartment = Module.new
      tenant_mod = Module.new { def self.current = '' }
      stub_const('Apartment', apartment)
      stub_const('Apartment::Tenant', tenant_mod)

      parsed = parse(formatter.call('INFO', time, nil, 'hello'))
      expect(parsed).not_to have_key('tenant')
    end
  end

  describe 'TaggedLogging integration' do
    it 'extracts request_id from the first tag when not in KEY:VALUE form' do
      Thread.current[:activesupport_tagged_logging_tags] = ['req-abc-123']
      parsed = parse(formatter.call('INFO', time, nil, '[req-abc-123] hello'))
      expect(parsed['request_id']).to eq('req-abc-123')
    end

    it 'parses KEY:VALUE tags into named fields (TENANT, CLIENT_ID, etc.)' do
      Thread.current[:activesupport_tagged_logging_tags] = ['req-1', 'TENANT: justburger', 'CLIENT_ID: web']
      parsed = parse(formatter.call('INFO', time, nil, '[req-1] [TENANT: justburger] [CLIENT_ID: web] hello'))

      expect(parsed['request_id']).to eq('req-1')
      expect(parsed['tenant']).to eq('justburger')
      expect(parsed['client_id']).to eq('web')
    end

    it 'strips the TaggedLogging prefix from the message field' do
      Thread.current[:activesupport_tagged_logging_tags] = ['req-1', 'TENANT: t']
      parsed = parse(formatter.call('INFO', time, nil, '[req-1] [TENANT: t] hello world'))
      expect(parsed['message']).to eq('hello world')
    end

    it 'works without tags' do
      parsed = parse(formatter.call('INFO', time, nil, 'hello'))
      expect(parsed).not_to have_key('request_id')
      expect(parsed).not_to have_key('tenant')
    end

    context 'Rails 7.1 — tags via current_tags method (not thread-local)' do
      # Rails 7.1 moved tags off Thread.current into IsolatedExecutionState,
      # exposed through the current_tags method that TaggedLogging::Formatter
      # mixes into the formatter instance. Simulate that here.
      let(:formatter) do
        described_class.new.tap do |f|
          tags = ['req-7-1', 'TENANT: moulie']
          f.define_singleton_method(:current_tags) { tags }
        end
      end

      before { Thread.current[:activesupport_tagged_logging_tags] = nil }

      it 'reads tags from current_tags when the thread-local is empty' do
        parsed = parse(formatter.call('INFO', time, nil, '[req-7-1] [TENANT: moulie] hello'))
        expect(parsed['request_id']).to eq('req-7-1')
        expect(parsed['tenant']).to eq('moulie')
      end

      it 'strips the tag prefix using current_tags' do
        parsed = parse(formatter.call('INFO', time, nil, '[req-7-1] [TENANT: moulie] Started GET'))
        expect(parsed['message']).to eq('Started GET')
      end
    end
  end

  describe 'Sidekiq context' do
    after do
      hide_const('Sidekiq') if defined?(Sidekiq)
      Thread.current[:sidekiq_tid] = nil
      Thread.current[:sidekiq_context] = nil
    end

    it 'omits sidekiq fields when Sidekiq is not loaded' do
      hide_const('Sidekiq') if defined?(Sidekiq)
      parsed = parse(formatter.call('INFO', time, nil, 'hello'))
      expect(parsed).not_to have_key('jid')
      expect(parsed).not_to have_key('job_class')
    end

    it 'reads jid/class from Sidekiq::Context.current (Sidekiq 6.5+/7)' do
      context_mod = Module.new do
        def self.current = { jid: 'abc123', class: 'Sqs::UpdateOrderStatusWorker' }
      end
      stub_const('Sidekiq', Module.new)
      stub_const('Sidekiq::Context', context_mod)
      Thread.current[:sidekiq_tid] = 'tid-xyz'

      parsed = parse(formatter.call('INFO', time, nil, 'start'))
      expect(parsed['jid']).to eq('abc123')
      expect(parsed['job_class']).to eq('Sqs::UpdateOrderStatusWorker')
      expect(parsed['tid']).to eq('tid-xyz')
    end

    it 'parses jid/class from the thread-local string context (Sidekiq 5.x)' do
      stub_const('Sidekiq', Module.new)
      Thread.current[:sidekiq_context] = ['Sqs::DeployMenuWorker JID-def456']
      Thread.current[:sidekiq_tid] = 'tid-5x'

      parsed = parse(formatter.call('INFO', time, nil, 'start'))
      expect(parsed['jid']).to eq('def456')
      expect(parsed['job_class']).to eq('Sqs::DeployMenuWorker')
      expect(parsed['tid']).to eq('tid-5x')
    end

    it 'omits jid/job_class when there is no active job (web process)' do
      stub_const('Sidekiq', Module.new)
      # No Sidekiq::Context, no thread-local context → web process
      parsed = parse(formatter.call('INFO', time, nil, 'hello'))
      expect(parsed).not_to have_key('jid')
      expect(parsed).not_to have_key('job_class')
    end
  end

  describe 'defaults: per-instance presets' do
    it 'includes preset fields in every emission' do
      sqs_formatter = described_class.new(defaults: { component: 'sqs', worker: 'OrderJob' })
      parsed = parse(sqs_formatter.call('INFO', time, nil, 'processing'))
      expect(parsed['component']).to eq('sqs')
      expect(parsed['worker']).to eq('OrderJob')
    end

    it 'allows per-call fields to override preset defaults' do
      sqs_formatter = described_class.new(defaults: { component: 'sqs' })
      parsed = parse(sqs_formatter.call('INFO', time, nil, message: 'x', component: 'redis'))
      expect(parsed['component']).to eq('redis')
    end
  end

  describe 'resilience' do
    it 'falls back to minimal JSON if a sub-step explodes' do
      # Force the OTel call to raise an error that escapes the rescue
      apartment = Module.new
      tenant_mod = Module.new { def self.current = raise 'tenant fail' }
      stub_const('Apartment', apartment)
      stub_const('Apartment::Tenant', tenant_mod)

      # Should still produce a valid JSON line, never raise
      output = formatter.call('INFO', time, nil, 'hello')
      parsed = parse(output)
      expect(parsed).to include('level' => 'INFO')
    end
  end
end
