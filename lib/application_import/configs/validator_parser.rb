module ApplicationImport
  module Configs
    class ValidatorParser
      include Checks
      include Constants

      UNIQUE_IN_FILE_KEYS = %i[ keys case_sensitive ].freeze

      def initialize(config, column_keys, errors)
        @config = config
        @column_keys = column_keys
        @errors = errors
      end

      def parse
        return add_error("validators", "must be a list") || [] unless @config.is_a?(Array)

        @config.each_with_index.filter_map { |spec, index| parse_validator(spec, "validators[#{index}]") }
      end

      private

      def parse_validator(spec, path)
        return add_error(path, "must be a mapping") unless spec.is_a?(Hash)
        return add_error(path, "needs exactly one of type, class") unless spec.key?("type") ^ spec.key?("class")

        parsed = build(spec, path)
        check_unique_in_file(parsed, path) if parsed[:type] == :unique_in_file
        parsed
      end

      def build(spec, path)
        {
          type: spec.key?("type") ? one_of(spec["type"], VALIDATOR_TYPES, "#{path}.type") : nil,
          class: class_name(spec["class"], "#{path}.class"),
          scope: one_of(spec.fetch("scope", DEFAULT_VALIDATOR_SCOPE), VALIDATOR_SCOPES, "#{path}.scope"),
          options: spec.except("type", "class", "scope").deep_symbolize_keys
        }
      end

      def check_unique_in_file(parsed, path)
        options = parsed[:options]
        add_error("#{path}.scope", "must be file for unique_in_file") unless parsed[:scope] == :file
        check_keys(options, UNIQUE_IN_FILE_KEYS, path)
        options[:keys] = names(options[:keys], "#{path}.keys").map(&:to_sym)
        check_columns(options[:keys], @column_keys, "#{path}.keys")
        boolean(options[:case_sensitive], "#{path}.case_sensitive") if options.key?(:case_sensitive)
      end
    end
  end
end
