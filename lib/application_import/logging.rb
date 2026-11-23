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
      # debug("text") or debug { "text" }: the logger only builds the line (and the block
      # only runs) when the level is enabled.
      define_method(level) do |message = nil, &block|
        logger&.public_send(level) { "#{log_prefix} #{block ? block.call : message}" }
        nil
      end
    end
  end
end
