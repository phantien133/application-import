module ApplicationImport
  module Configs
    # Parses the definition's mapper: nil, or a mapping with exactly one of
    #   type:  rename (attributes: { from: to }, only: true/false)
    #   class: a Mappers::Base subclass; other keys are its options
    class MapperParser
      include Checks

      BUILTIN = { rename: "ApplicationImport::Mappers::Rename" }.freeze
      RENAME_KEYS = %i[ attributes only ].freeze

      class << self
        def resolve!(spec)
          return if spec.nil?

          spec[:class] = ClassResolver.resolve!(spec[:class], base: "ApplicationImport::Mappers::Base",
            error: Errors::InvalidMapperError)
        end
      end

      def initialize(config, errors)
        @config = config
        @errors = errors
      end

      def parse
        return if @config.nil?
        return add_error("mapper", "must be a mapping") unless @config.is_a?(Hash)
        return add_error("mapper", "needs exactly one of type, class") unless @config.key?("type") ^ @config.key?("class")

        @config.key?("type") ? builtin : custom
      end

      private

      def custom
        return add_error("mapper.class", "must be a class name") if @config["class"].nil?

        name = class_name(@config["class"], "mapper.class")
        return if name.nil?

        { type: nil, class: name, options: @config.except("class").deep_symbolize_keys }
      end

      def builtin
        type = one_of(@config["type"], BUILTIN.keys.map(&:to_s), "mapper.type")
        return unless type

        { type:, class: BUILTIN.fetch(type), options: rename_options(@config.except("type").symbolize_keys) }
      end

      def rename_options(options)
        check_keys(options, RENAME_KEYS, "mapper")
        boolean(options[:only], "mapper.only") if options.key?(:only)
        renames = options[:attributes]
        return add_error("mapper.attributes", "must be a non-empty mapping of names") || options unless renames?(renames)

        options.merge(attributes: renames.to_h { |from, to| [ from.to_sym, to.to_sym ] })
      end

      def renames?(renames)
        renames.is_a?(Hash) && renames.any? && renames.all? { |from, to| name?(from) && name?(to) }
      end

      def name?(value)
        (value.is_a?(String) || value.is_a?(Symbol)) && value.to_s.present?
      end
    end
  end
end
