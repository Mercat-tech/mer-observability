require 'spec_helper'
require 'tmpdir'

RSpec.describe MerObservability::Configuration do
  let(:relevant_env_keys) do
    %w[
      OTEL_SERVICE_NAME
      OTEL_EXPORTER_OTLP_ENDPOINT
      OTEL_TRACES_SAMPLER_ARG
      OTEL_LOG_INJECTION
      OTEL_RUBY_RUNTIME_METRICS
      OTEL_RUBY_RUNTIME_METRICS_INTERVAL
      MER_LOG_FORMAT
      APP_VERSION
      GIT_SHA
      RENV
      RAILS_ENV
    ]
  end

  around do |example|
    saved = relevant_env_keys.to_h { |k| [k, ENV.fetch(k, nil)] }
    relevant_env_keys.each { |k| ENV.delete(k) }
    example.run
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  describe '#initialize defaults' do
    subject(:config) { described_class.new }

    it 'defaults service_name to "unknown-service" when Rails is not loaded' do
      hide_const('Rails')
      expect(config.service_name).to eq('unknown-service')
    end

    it 'defaults service_version to "unknown" when no source available' do
      hide_const('Rails')
      expect(config.service_version).to eq('unknown')
    end

    it 'defaults environment to "development" when RENV/RAILS_ENV unset' do
      expect(config.environment).to eq('development')
    end

    it 'is disabled when no endpoint is configured' do
      expect(config.enabled).to eq(false)
    end

    it 'enables capture_tenant by default' do
      expect(config.capture_tenant).to eq(true)
    end

    it 'enables log_injection by default' do
      expect(config.log_injection).to eq(true)
    end

    it 'enables runtime_metrics by default' do
      expect(config.runtime_metrics_enabled).to eq(true)
    end

    it 'defaults sampler_ratio to 1.0' do
      expect(config.sampler_ratio).to eq(1.0)
    end

    it 'defaults runtime_metrics_interval to 30 seconds' do
      expect(config.runtime_metrics_interval).to eq(30)
    end

    it 'defaults log_format to "text" in development' do
      expect(config.log_format).to eq('text')
    end
  end

  describe 'log_format defaults by environment' do
    it 'defaults to "json" when RAILS_ENV=production' do
      ENV['RAILS_ENV'] = 'production'
      expect(described_class.new.log_format).to eq('json')
    end

    it 'defaults to "json" when RENV=stage' do
      ENV['RENV'] = 'stage'
      expect(described_class.new.log_format).to eq('json')
    end

    it 'defaults to "text" when RAILS_ENV=development' do
      ENV['RAILS_ENV'] = 'development'
      expect(described_class.new.log_format).to eq('text')
    end

    it 'defaults to "text" when RAILS_ENV=test' do
      ENV['RAILS_ENV'] = 'test'
      expect(described_class.new.log_format).to eq('text')
    end

    it 'honors MER_LOG_FORMAT override even in production' do
      ENV['RAILS_ENV'] = 'production'
      ENV['MER_LOG_FORMAT'] = 'text'
      expect(described_class.new.log_format).to eq('text')
    end

    it 'honors MER_LOG_FORMAT override in development' do
      ENV['MER_LOG_FORMAT'] = 'json'
      expect(described_class.new.log_format).to eq('json')
    end
  end

  describe 'environment-driven configuration' do
    it 'reads OTEL_SERVICE_NAME' do
      ENV['OTEL_SERVICE_NAME'] = 'my-service'
      expect(described_class.new.service_name).to eq('my-service')
    end

    it 'reads OTEL_EXPORTER_OTLP_ENDPOINT and flips enabled' do
      ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] = 'http://collector:4317'
      cfg = described_class.new
      expect(cfg.endpoint).to eq('http://collector:4317')
      expect(cfg.enabled).to eq(true)
    end

    it 'treats empty endpoint string as disabled' do
      ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] = ''
      expect(described_class.new.enabled).to eq(false)
    end

    it 'parses OTEL_TRACES_SAMPLER_ARG as float' do
      ENV['OTEL_TRACES_SAMPLER_ARG'] = '0.1'
      expect(described_class.new.sampler_ratio).to eq(0.1)
    end

    it 'reads OTEL_LOG_INJECTION=false to disable injection' do
      ENV['OTEL_LOG_INJECTION'] = 'false'
      expect(described_class.new.log_injection).to eq(false)
    end

    it 'reads OTEL_RUBY_RUNTIME_METRICS=false to disable metrics' do
      ENV['OTEL_RUBY_RUNTIME_METRICS'] = 'false'
      expect(described_class.new.runtime_metrics_enabled).to eq(false)
    end

    it 'reads OTEL_RUBY_RUNTIME_METRICS_INTERVAL as integer' do
      ENV['OTEL_RUBY_RUNTIME_METRICS_INTERVAL'] = '60'
      expect(described_class.new.runtime_metrics_interval).to eq(60)
    end

    it 'prefers RENV over RAILS_ENV' do
      ENV['RENV'] = 'stage'
      ENV['RAILS_ENV'] = 'production'
      expect(described_class.new.environment).to eq('stage')
    end

    it 'falls back to RAILS_ENV when RENV is unset' do
      ENV['RAILS_ENV'] = 'production'
      expect(described_class.new.environment).to eq('production')
    end
  end

  describe 'service_version autodiscovery' do
    it 'prefers APP_VERSION when set' do
      ENV['APP_VERSION'] = 'v1.2.3'
      ENV['GIT_SHA']     = 'abcdef0'
      expect(described_class.new.service_version).to eq('v1.2.3')
    end

    it 'falls back to GIT_SHA when APP_VERSION is unset' do
      ENV['GIT_SHA'] = 'abcdef0'
      expect(described_class.new.service_version).to eq('abcdef0')
    end

    it 'returns "unknown" when no source resolves' do
      hide_const('Rails')
      expect(described_class.new.service_version).to eq('unknown')
    end

    it 'reads REVISION file under Rails.root if present' do
      stub_rails_root_with(revision: "deadbeef\n")
      expect(described_class.new.service_version).to eq('deadbeef')
    end
  end

  describe 'service_name with Rails + Sidekiq' do
    it 'uses Rails app name dasherized when not in a Sidekiq server' do
      stub_rails_app_named('MyService')
      expect(described_class.new.service_name).to eq('my-service')
    end

    it 'appends -sidekiq suffix when running inside Sidekiq server' do
      stub_rails_app_named('MyService')
      sidekiq_mod = Module.new { def self.server? = false }
      stub_const('Sidekiq', sidekiq_mod)
      allow(Sidekiq).to receive(:server?).and_return(true)
      expect(described_class.new.service_name).to eq('my-service-sidekiq')
    end
  end

  def stub_rails_app_named(class_name)
    application = Class.new
    application.define_singleton_method(:module_parent_name) { class_name }
    rails_double = double('Rails')
    allow(rails_double).to receive_message_chain(:application, :class).and_return(application)
    stub_const('Rails', rails_double)
  end

  def stub_rails_root_with(revision: nil)
    root_path = Pathname.new(Dir.mktmpdir)
    File.write(root_path.join('REVISION'), revision) if revision

    application = Class.new
    application.define_singleton_method(:module_parent_name) { 'MerUsers' }

    rails_double = double('Rails')
    allow(rails_double).to receive(:respond_to?).with(:root).and_return(true)
    allow(rails_double).to receive(:root).and_return(root_path)
    allow(rails_double).to receive_message_chain(:application, :class).and_return(application)
    stub_const('Rails', rails_double)
  end
end
