require 'rails'

module MerObservability
  class Railtie < ::Rails::Railtie
    initializer 'mer_observability.configure_otel', after: :initialize_logger do
      MerObservability::Setup.call(MerObservability.config)
    end
  end
end
