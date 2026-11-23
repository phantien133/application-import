module ApplicationImport
  # Leveled log helpers for import components. The including class sets @logger
  # (injected, defaulting to ApplicationImport.logger) and may override #log_prefix.
  module Logging
    LEVELS = %i[ debug info warn error fatal ].freeze

    attr_reader :logger

    private

    def log_prefix
      name = definition&.name if respond_to?(:definition)
      name ? "[#{self.class.name}:#{name}]" : "[#{self.class.name}]"
    end

    LEVELS.each do |level|
      # Block form: the message is only built when the level is enabled.
      define_method(level) do |message|
        logger&.public_send(level) { "#{log_prefix} #{message}" }
        nil
      end
    end
  end
end
