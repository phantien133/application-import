module ApplicationImport
  module Configs
    # Parses the definition's transformers: a list of entries with exactly one of
    #   type:  a built-in transformer (concat, default, map, normalize, context)
    #   class: a Transformers::Base subclass; other keys are its options
    class TransformerParser
      include Checks

      BUILTIN = {
        concat: "ApplicationImport::Transformers::Concat",
        default: "ApplicationImport::Transformers::Default",
        map: "ApplicationImport::Transformers::Map",
        normalize: "ApplicationImport::Transformers::Normalize",
        context: "ApplicationImport::Transformers::Context"
      }.freeze
      KEYS = {
        concat: %i[ from to separator ],
        default: %i[ attribute value ],
        map: %i[ attribute values to case_sensitive strict ],
        normalize: %i[ attributes with ],
        context: %i[ key to ]
      }.freeze
      REQUIRED = {
        concat: %i[ from to ], default: %i[ attribute value ], map: %i[ attribute values ],
        normalize: %i[ attributes with ], context: %i[ key to ]
      }.freeze

      class << self
        def resolve!(transformers)
          transformers.each do |spec|
            spec[:class] = ClassResolver.resolve!(spec[:class], base: "ApplicationImport::Transformers::Base",
              error: Errors::InvalidTransformerError)
          end
        end
      end

      def initialize(config, errors)
        @config = config
        @errors = errors
      end

      def parse
        return [] if @config.nil?
        return add_error("transformers", "must be a list") || [] unless @config.is_a?(Array)

        @config.each_with_index.filter_map { |spec, index| parse_transformer(spec, "transformers[#{index}]") }
      end

      private

      def parse_transformer(spec, path)
        return add_error(path, "must be a mapping") unless spec.is_a?(Hash)
        return add_error(path, "needs exactly one of type, class") unless spec.key?("type") ^ spec.key?("class")

        spec.key?("type") ? builtin(spec, path) : custom(spec, path)
      end

      def custom(spec, path)
        return add_error("#{path}.class", "must be a class name") if spec["class"].nil?

        name = class_name(spec["class"], "#{path}.class")
        return if name.nil?

        { type: nil, class: name, options: spec.except("class").deep_symbolize_keys }
      end

      def builtin(spec, path)
        type = one_of(spec["type"], BUILTIN.keys.map(&:to_s), "#{path}.type")
        return unless type

        options = builtin_options(type, spec.except("type"), path)
        { type:, class: BUILTIN.fetch(type), options: }
      end

      def builtin_options(type, spec, path)
        options = spec.symbolize_keys
        check_keys(options, KEYS.fetch(type), path)
        missing = REQUIRED.fetch(type) - options.keys
        add_error(path, "needs #{missing.join(", ")}") if missing.any?
        normalize_options(type, options, path)
      end

      def normalize_options(type, options, path)
        %i[ from attributes ].each { |key| options[key] = names(options[key], "#{path}.#{key}").map(&:to_sym) if options.key?(key) }
        %i[ to attribute key ].each { |key| options[key] = name(options[key], "#{path}.#{key}") if options.key?(key) }
        check_type_options(type, options, path)
        options
      end

      def check_type_options(type, options, path)
        case type
        when :map then check_map(options, path)
        when :normalize then check_normalize(options, path)
        when :concat
          add_error("#{path}.separator", "must be a string") if options.key?(:separator) && !options[:separator].is_a?(String)
        end
      end

      def check_map(options, path)
        values = options[:values]
        add_error("#{path}.values", "must be a non-empty mapping") unless values.is_a?(Hash) && values.any?
        options[:values] = values.to_h { |from, to| [ from.to_s, to ] } if values.is_a?(Hash)
        %i[ case_sensitive strict ].each { |key| boolean(options[key], "#{path}.#{key}") if options.key?(key) }
      end

      def check_normalize(options, path)
        operations = names(options[:with], "#{path}.with")
        unknown = operations - Transformers::Normalize::OPERATIONS
        add_error("#{path}.with", "has unknown operations: #{unknown.join(", ")}") if unknown.any?
        options[:with] = operations
      end

      def name(value, path)
        return value.to_sym if (value.is_a?(String) || value.is_a?(Symbol)) && value.to_s.present?

        add_error(path, "must be a name")
      end
    end
  end
end
