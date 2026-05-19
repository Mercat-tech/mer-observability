require_relative 'lib/mer_observability/version'

Gem::Specification.new do |s|
  s.name        = 'mer_observability'
  s.version     = MerObservability::VERSION
  s.authors     = ['Mercat-tech']
  s.email       = ['tech@mercat.cl']
  s.homepage    = 'https://github.com/Mercat-tech/mer-observability'
  s.summary     = 'OpenTelemetry instrumentation for Rails microservices.'
  s.description = 'Plug-and-play OTel tracing for Rails microservices. ' \
                  'Auto-instruments Rails, ActiveRecord, Sidekiq, Redis and HTTP clients. ' \
                  'Captures the Apartment tenant on every span.'
  s.license     = 'MIT'

  s.required_ruby_version = '>= 3.3'

  s.files = Dir['{lib}/**/*', 'LICENSE', 'README.md']

  s.add_dependency 'opentelemetry-exporter-otlp',                  '~> 0.28'
  s.add_dependency 'opentelemetry-exporter-otlp-metrics',          '~> 0.4'
  s.add_dependency 'opentelemetry-instrumentation-action_pack',    '~> 0.10'
  s.add_dependency 'opentelemetry-instrumentation-action_view',    '~> 0.10'
  s.add_dependency 'opentelemetry-instrumentation-active_record',  '~> 0.8'
  s.add_dependency 'opentelemetry-instrumentation-active_support', '~> 0.10'
  s.add_dependency 'opentelemetry-instrumentation-faraday',        '~> 0.25'
  s.add_dependency 'opentelemetry-instrumentation-http',           '~> 0.24'
  s.add_dependency 'opentelemetry-instrumentation-net_http',       '~> 0.22'
  s.add_dependency 'opentelemetry-instrumentation-rack',           '~> 0.25'
  s.add_dependency 'opentelemetry-instrumentation-rails',          '~> 0.32'
  s.add_dependency 'opentelemetry-instrumentation-redis',          '~> 0.25'
  s.add_dependency 'opentelemetry-instrumentation-sidekiq',        '~> 0.25'
  s.add_dependency 'opentelemetry-metrics-sdk',                   '~> 0.5'
  s.add_dependency 'opentelemetry-sdk',                           '~> 1.4'
  s.add_dependency 'rails',                                       '>= 7.0'
  s.metadata['rubygems_mfa_required'] = 'true'
end
