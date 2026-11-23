module ApplicationImport
  module Configs
    class OnErrorParser
      include Checks
      include Constants

      KEYS = %w[ default allow skip row_errors max_errors ].freeze

      def initialize(config, errors)
        @config = config.nil? ? DEFAULT_ON_ERROR : config
        @errors = errors
      end

      def parse
        return ErrorPolicy.new(default: action(@config, "on_error")) unless @config.is_a?(Hash)

        check_keys(@config, KEYS, "on_error")
        allow = codes("allow")
        skip = codes("skip")
        overlap = allow & skip
        add_error("on_error", "lists codes in both allow and skip: #{overlap.join(", ")}") if overlap.any?
        ErrorPolicy.new(default: action(@config.fetch("default", DEFAULT_ON_ERROR), "on_error.default"), allow:, skip:,
          row_errors: one_of(@config.fetch("row_errors", DEFAULT_ROW_ERRORS), ROW_ERRORS, "on_error.row_errors") || :first,
          max_errors: max_errors)
      end

      private

      # Absent (or null): no limit.
      def max_errors
        value = @config["max_errors"]
        value.nil? ? nil : integer(value, "on_error.max_errors")
      end

      def action(value, path)
        one_of(value, ON_ERROR_MODES, path) || :abort
      end

      def codes(key)
        @config.key?(key) ? names(@config[key], "on_error.#{key}").map(&:to_sym) : []
      end
    end
  end
end
