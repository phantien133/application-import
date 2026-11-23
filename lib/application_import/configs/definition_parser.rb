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
        check_stream(parsed)
        check_numbers(parsed)
        check_rename(parsed)
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
        file = parsed[:file]
        add_error("file.assign", "is only used with unknown_headers: assign") if file[:assign] && file[:unknown_headers] != :assign
        return unless file[:unknown_headers] == :assign

        return add_error("file.unknown_headers", "assign needs output.model") if parsed[:output][:model].nil?

        warn_assign_all if file[:assign].nil?
      end

      def check_stream(parsed)
        return unless parsed[:output][:stream] && parsed[:validators][:verify].any?

        add_error("output.stream", "cannot be used with verify validators (rows are written before verify)")
      end

      # A decimal column reads with file.numbers overridden by its own separators, the
      # decimal one defaulting to ".": the merged pair must differ too (a clash within one
      # level is already reported there).
      def check_numbers(parsed)
        numbers = parsed[:file][:numbers] || {}
        parsed[:columns].each do |column|
          next unless column.type == :decimal

          thousands = merged_clash(numbers, column.options.slice(:decimal_separator, :thousands_separator))
          next unless thousands

          add_error("columns.#{column.key}", "thousands_separator #{thousands.inspect} is also its decimal " \
                                             "separator (file.numbers, the column's own, default \".\")")
        end
      end

      # The clashing separator of the merged pair, unless one level clashes by itself.
      def merged_clash(numbers, own)
        return if [ numbers, own ].any? { |format| format.size == 2 && format.values.uniq.one? }

        format = numbers.merge(own)
        format[:thousands_separator] if format[:thousands_separator] == format.fetch(:decimal_separator, ".")
      end

      # A rename target that is a declared column not renamed away itself would silently
      # replace that column's value.
      def check_rename(parsed)
        mapper = parsed[:mapper]
        return unless mapper && mapper[:type] == :rename && !mapper[:options][:only]

        renames = mapper[:options][:attributes] || {}
        clashes = renames.values & (@column_keys - renames.keys)
        add_error("mapper.attributes", "would overwrite the columns #{clashes.join(", ")} (rename them too, or use only: true)") if clashes.any?
      end

      def warn_assign_all
        ApplicationImport.logger&.warn("[ApplicationImport] #{@name}: unknown_headers: assign without file.assign allow / ignore " \
                                       "- every file header naming a model attribute can be assigned")
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
        output[:model] = ClassResolver.resolve_model!(output[:model], path: "#{@name}: output.model")
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
