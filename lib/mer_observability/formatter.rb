require 'mer_observability/json_formatter'
require 'mer_observability/text_formatter'

module MerObservability
  # Factory that returns the appropriate logger formatter based on the
  # `log_format` configuration. The default is `json` in stage/production
  # and `text` in development/test, but can be overridden via the
  # `MER_LOG_FORMAT` environment variable.
  #
  # Usage in a Rails app:
  #
  #   # config/environments/production.rb
  #   config.log_formatter = MerObservability::Formatter.build
  #
  #   # config/environments/development.rb  →  no change needed, default is text
  #
  # For custom auxiliary loggers (Sqs, Redis events, etc.):
  #
  #   logger = Logger.new(STDOUT)
  #   logger.formatter = MerObservability::Formatter.build(defaults: { component: 'sqs' })
  module Formatter
    JSON_FORMAT = 'json'.freeze
    TEXT_FORMAT = 'text'.freeze

    def self.build(defaults: {})
      case MerObservability.config.log_format.to_s.downcase
      when JSON_FORMAT
        JsonFormatter.new(defaults: defaults)
      else
        # `defaults` not honored by TextFormatter (text is positional, hard
        # to inject arbitrary fields without breaking readability). Callers
        # that need structured fields should use json mode.
        TextFormatter.new
      end
    end
  end
end
