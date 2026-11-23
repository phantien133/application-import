module ApplicationImport
  module Configs
    class ValidatorParser
      include Checks
      include Constants

      UNIQUE_IN_FILE_KEYS = %i[ keys case_sensitive ].freeze
      MODEL_KEYS = %i[ model context except skip ].freeze

      class << self
        # Resolves validator classes per stage and the model of model validators (their
        # own model or output.model, one of them required).
        def resolve!(validators, output_model:, name:)
          validators.each do |stage, specs|
            specs.each_with_index do |spec, index|
              spec[:class] = ClassResolver.resolve!(spec[:class], base: Constants::VALIDATOR_BASES.fetch(stage),
                error: Errors::InvalidValidatorError)
              resolve_model!(spec, output_model, "#{name}: validators.#{stage}[#{index}]") if spec[:type] == :model
            end
          end
        end

        private

        def resolve_model!(spec, output_model, path)
          model = spec[:options][:model] = ClassResolver.resolve_model!(spec[:options][:model], path: "#{path}.model")
          raise Errors::ConfigError, "#{path}.model is required without output.model" unless model || output_model
        end
      end

      def initialize(config, column_keys, errors)
        @config = config
        @column_keys = column_keys
        @errors = errors
      end

      def parse
        config = mapping(@config, "validators")
        check_keys(config, VALIDATOR_STAGES, "validators")
        VALIDATOR_STAGES.to_h { |stage| [ stage.to_sym, parse_stage(stage.to_sym, config[stage]) ] }
      end

      private

      def parse_stage(stage, list)
        path = "validators.#{stage}"
        return [] if list.nil?
        return add_error(path, "must be a list") || [] unless list.is_a?(Array)

        list.each_with_index.filter_map { |spec, index| parse_validator(stage, spec, "#{path}[#{index}]") }
      end

      def parse_validator(stage, spec, path)
        return add_error(path, "must be a mapping") unless spec.is_a?(Hash)
        return add_error(path, "needs exactly one of type, class") unless spec.key?("type") ^ spec.key?("class")

        parsed = spec.key?("type") ? builtin(stage, spec["type"], path) : custom(spec["class"], path)
        parsed.merge(options: options(parsed[:type], spec, path))
      end

      def options(type, spec, path)
        options = spec.except("type", "class").deep_symbolize_keys
        check_unique_in_file(options, path) if type == :unique_in_file
        check_model(options, path) if type == :model
        options
      end

      def builtin(stage, value, path)
        builtins = BUILTIN_VALIDATORS.fetch(stage)
        return add_error("#{path}.type", "is not available for #{stage} validators") || {} if builtins.empty?

        type = one_of(value, builtins.keys.map(&:to_s), "#{path}.type")
        { type:, class: type && builtins[type] }
      end

      def custom(value, path)
        add_error("#{path}.class", "must be a class name") if value.nil?
        { type: nil, class: class_name(value, "#{path}.class") }
      end

      # model (class name, resolved later; falls back to output.model), context, except.
      def check_model(options, path)
        check_keys(options, MODEL_KEYS, path)
        options[:model] = class_name(options[:model], "#{path}.model") if options.key?(:model)
        check_context(options, "#{path}.context")
        %i[ except skip ].each { |key| options[key] = names(options[key], "#{path}.#{key}").map(&:to_sym) if options.key?(key) }
      end

      def check_context(options, path)
        return unless options.key?(:context)

        contexts = Array(options[:context])
        valid = contexts.any? && contexts.all? { |context| (context.is_a?(String) || context.is_a?(Symbol)) && context.present? }
        add_error(path, "must be a name or a non-empty list of names") unless valid
      end

      def check_unique_in_file(options, path)
        check_keys(options, UNIQUE_IN_FILE_KEYS, path)
        options[:keys] = names(options[:keys], "#{path}.keys").map(&:to_sym)
        check_columns(options[:keys], @column_keys, "#{path}.keys") if @column_keys
        boolean(options[:case_sensitive], "#{path}.case_sensitive") if options.key?(:case_sensitive)
      end
    end
  end
end
