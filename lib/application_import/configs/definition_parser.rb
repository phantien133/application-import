module ApplicationImport
  module Configs
    class DefinitionParser
      include Checks
      include Constants

      ROOT_KEYS = %w[ handler file columns validators output on_error ].freeze
      FILE_KEYS = %w[ checker formats name_pattern max_size format reader max_rows encoding headers csv xlsx ].freeze
      XLSX_KEYS = %w[ sheet ].freeze
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
          file: parse_file(mapping(@config["file"], "file")),
          columns:,
          validators: parse_validators,
          output: parse_output(mapping(@config["output"], "output")),
          on_error: OnErrorParser.new(@config["on_error"], @errors).parse
        }
      end

      def parse_validators
        ValidatorParser.new(@config["validators"], @column_keys, @errors).parse
      end

      def parse_file(file)
        check_keys(file, FILE_KEYS, "file")
        parsed = { checker: class_name(file["checker"], "file.checker"), **file_checks(file), **file_reading(file) }
        check_format_allowed(parsed)
        parsed
      end

      # Settings used by the FileChecker (nil = check skipped).
      def file_checks(file)
        {
          formats: formats(file["formats"]),
          name_pattern: regexp(file["name_pattern"], "file.name_pattern"),
          max_size: optional_integer(file["max_size"], "file.max_size")
        }
      end

      # Settings used by the reader: a custom `reader` class wins over the one `format` picks.
      def file_reading(file)
        {
          format: one_of(file.fetch("format", DEFAULT_FORMAT), FORMATS, "file.format"),
          reader: class_name(file["reader"], "file.reader"),
          max_rows: integer(file.fetch("max_rows", DEFAULT_MAX_ROWS), "file.max_rows"),
          encoding: encoding(file.fetch("encoding", DEFAULT_ENCODING)),
          headers: boolean(file.fetch("headers", true), "file.headers"),
          csv: CsvOptionsParser.new(file["csv"], @errors).parse,
          xlsx: reader_options(file["xlsx"], XLSX_KEYS, "file.xlsx")
        }
      end

      def check_format_allowed(parsed)
        format, formats = parsed.values_at(:format, :formats)
        return if format.nil? || formats.blank? || formats.include?(format)

        add_error("file.format", "must be one of file.formats (#{formats.join(", ")})")
      end

      def optional_integer(value, path)
        integer(value, path) unless value.nil?
      end

      def formats(value)
        return if value.nil?

        names(value, "file.formats").filter_map { |format| one_of(format, FORMATS, "file.formats") }.uniq
      end

      def encoding(value)
        Encoding.find(value.to_s).name
      rescue ArgumentError
        add_error("file.encoding", "is not a known encoding: #{value}")
      end

      def reader_options(value, allowed, path)
        options = mapping(value, path)
        check_keys(options, allowed, path)
        options.symbolize_keys
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
        resolve_validators(parsed[:validators])
        parsed[:output][:model] = ClassResolver.resolve!(parsed[:output][:model], base: "ActiveRecord::Base")
      end

      def resolve_validators(validators)
        validators.each do |stage, specs|
          specs.each do |spec|
            spec[:class] = ClassResolver.resolve!(spec[:class], base: VALIDATOR_BASES.fetch(stage),
              error: Errors::InvalidValidatorError)
          end
        end
      end

      def resolve(name, base, error)
        ClassResolver.resolve!(name, base:, default: base, error:)
      end
    end
  end
end
