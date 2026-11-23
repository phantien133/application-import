module Logs
  module ServiceLog
    extend ActiveSupport::Concern

    LEVELS = %i[debug info warn error fatal].freeze

    private

    def logger
      @logger ||= Rails.logger
    end

    # service_id already carries the class name: "MyService#<uuid v7>"
    def log_prefix
      "[#{service_id}]"
    end

    LEVELS.each do |level|
      # Block form: the message string is only built when the level is enabled.
      define_method(level) do |message|
        logger.public_send(level) { "#{log_prefix} #{message}" }
      end
    end
  end
end
