$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'rspec'

# Load OpenTelemetry SDK so the constants are available; tests stub the
# parts that would otherwise hit real exporters.
require 'opentelemetry-sdk'
require 'active_support/core_ext/string/inflections'

# The gem requires Rails for its Railtie; we don't want a full Rails
# boot in specs, so we load only the pieces we need and the Railtie is
# guarded by `if defined?(Rails)` in lib/mer_observability.rb.
# Specs that need Rails-aware behavior stub it locally.

require 'mer_observability'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  # Reset gem singleton state between tests so env-driven configuration
  # is re-read on each example.
  config.before do
    MerObservability.reset! if MerObservability.respond_to?(:reset!)
  end
end
