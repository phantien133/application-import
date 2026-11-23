module ApplicationImport
  module Configs
    class DefinitionParser
      include Checks
      include Constants

      ROOT_KEYS = %w[ handler file columns transformers mapper validators output on_error ].freeze

      def initialize(name, config)
        @name = name
        @errors = []
        @config = config.is_a?(Hash) ? config.deep_dup.deep_stringify_keys : (add_error("config", "must be a mapping") || {})
      end

      def parse
        check_keys(@config, ROOT_KEYS, "config")
        parsed = parse_sections
        check_assign(parsed)
        raise Errors::ConfigError, "#{@name}: #{@errors.join("; ")}" if @errors.any?

        resolve_classes(parsed)
        Ractor.make_shareable(parsed)
      end

      private

      def parse_sections
        {
          handler: class_name(@config["handler"], "handler"),
          file: FileParser.new(@config["file"], @errors).parse,
          columns: parse_columns,
          transformers: parse_transformers,
          mapper: MapperParser.new(@config["mapper"], @errors).parse,
          validators: parse_validators,
          output: OutputParser.new(@config["output"], @column_keys, @errors).parse,
          on_error: OnErrorParser.new(@config["on_error"], @errors).parse
        }
      end

      def check_assign(parsed)
        return unless parsed[:file][:unknown_headers] == :assign && parsed[:output][:model].nil?

        add_error("file.unknown_headers", "assign needs output.model")
      end

      def parse_columns
        ColumnParser.new(@config["columns"], @errors).parse.tap { |columns| @column_keys = columns.map(&:key) }
      end

      def parse_transformers
        TransformerParser.new(@config["transformers"], @errors).parse
      end

      # Validator keys are checked against the declared columns only without transformers
      # or mapper: those can produce other names, checked when the import runs.
      def parse_validators
        static = @config["transformers"].blank? && @config["mapper"].nil?
        ValidatorParser.new(@config["validators"], static ? @column_keys : nil, @errors).parse
      end

      def resolve_classes(parsed)
        parsed[:handler] = resolve(parsed[:handler], Handler, Errors::InvalidHandlerError)
        parsed[:file][:checker] = resolve(parsed[:file][:checker], FileChecker, Errors::InvalidFileCheckerError)
        parsed[:file][:reader] = ClassResolver.resolve!(parsed[:file][:reader], base: Readers::Base, error: Errors::InvalidReaderError)
        resolve_references(parsed)
      end

      def resolve_references(parsed)
        resolve_output(parsed[:output])
        resolve_casters(parsed[:columns])
        TransformerParser.resolve!(parsed[:transformers])
        MapperParser.resolve!(parsed[:mapper])
        ValidatorParser.resolve!(parsed[:validators], output_model: parsed[:output][:model], name: @name)
      end

      def resolve_output(output)
        output[:model] = ClassResolver.resolve!(output[:model], base: "ActiveRecord::Base")
        OutputParser.check_model_attributes!(output, name: @name)
      end

      def resolve_casters(columns)
        columns.each do |column|
          next unless column.options[:caster]

          column.options[:caster] = ClassResolver.resolve!(column.options[:caster], base: "ApplicationImport::Casters::Base",
            error: Errors::InvalidCasterError)
        end
      end

      def resolve(name, base, error)
        ClassResolver.resolve!(name, base:, default: base, error:)
      end
    end
  end
end
