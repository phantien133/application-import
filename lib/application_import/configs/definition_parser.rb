module ApplicationImport
  module Configs
    class DefinitionParser
      include Checks
      include Constants

      ROOT_KEYS = %w[ handler file columns validators output on_error ].freeze
      OUTPUT_KEYS = %w[ mode model batch_size upsert ].freeze
      UPSERT_KEYS = %w[ conflict_target update ].freeze

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
        columns = ColumnParser.new(@config["columns"], @errors).parse
        @column_keys = columns.map(&:key)
        {
          handler: class_name(@config["handler"], "handler"),
          file: FileParser.new(@config["file"], @errors).parse,
          columns:,
          validators: parse_validators,
          output: parse_output(mapping(@config["output"], "output")),
          on_error: OnErrorParser.new(@config["on_error"], @errors).parse
        }
      end

      def check_assign(parsed)
        return unless parsed[:file][:unknown_headers] == :assign && parsed[:output][:model].nil?

        add_error("file.unknown_headers", "assign needs output.model")
      end

      def parse_validators
        ValidatorParser.new(@config["validators"], @column_keys, @errors).parse
      end

      def parse_output(output)
        check_keys(output, OUTPUT_KEYS, "output")
        mode = one_of(output.fetch("mode", DEFAULT_OUTPUT_MODE), OUTPUT_MODES, "output.mode")
        model = class_name(output["model"], "output.model")
        add_error("output.model", "is required when mode is database") if mode == :database && model.nil?
        {
          mode:,
          model:,
          batch_size: integer(output.fetch("batch_size", DEFAULT_BATCH_SIZE), "output.batch_size"),
          upsert: upsert(output["upsert"])
        }
      end

      def upsert(value)
        return if value.nil?

        upsert = mapping(value, "output.upsert")
        check_keys(upsert, UPSERT_KEYS, "output.upsert")
        update = upsert.key?("update") ? names(upsert["update"], "output.upsert.update").map(&:to_sym) : []
        check_columns(update, @column_keys, "output.upsert.update")
        { conflict_target: names(upsert["conflict_target"], "output.upsert.conflict_target").map(&:to_sym), update: }
      end

      def resolve_classes(parsed)
        parsed[:handler] = resolve(parsed[:handler], Handler, Errors::InvalidHandlerError)
        parsed[:file][:checker] = resolve(parsed[:file][:checker], FileChecker, Errors::InvalidFileCheckerError)
        parsed[:file][:reader] = ClassResolver.resolve!(parsed[:file][:reader], base: Readers::Base, error: Errors::InvalidReaderError)
        resolve_references(parsed)
      end

      def resolve_references(parsed)
        parsed[:output][:model] = ClassResolver.resolve!(parsed[:output][:model], base: "ActiveRecord::Base")
        resolve_casters(parsed[:columns])
        ValidatorParser.resolve!(parsed[:validators], output_model: parsed[:output][:model], name: @name)
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
