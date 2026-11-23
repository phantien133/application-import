module ApplicationImport
  module Configs
    # Parses the definition's file section.
    class FileParser
      include Checks
      include Constants

      KEYS = %w[ checker formats name_pattern max_size format reader encoding headers require_all_headers
        unknown_headers extra_cells csv xlsx ].freeze
      XLSX_KEYS = %w[ sheet ].freeze

      def initialize(config, errors)
        @errors = errors
        @file = mapping(config, "file")
      end

      def parse
        check_keys(@file, KEYS, "file")
        parsed = { checker: class_name(@file["checker"], "file.checker"), **checks, **reading, **headers }
        check_format_allowed(parsed)
        parsed
      end

      private

      # Settings used by the FileChecker (nil = check skipped).
      def checks
        {
          formats: formats(@file["formats"]),
          name_pattern: regexp(@file["name_pattern"], "file.name_pattern"),
          max_size: optional_integer(@file["max_size"], "file.max_size")
        }
      end

      # Settings used by the reader: a custom `reader` class wins over the one `format` picks.
      def reading
        {
          format: one_of(@file.fetch("format", DEFAULT_FORMAT), FORMATS, "file.format"),
          reader: class_name(@file["reader"], "file.reader"),
          encoding: encoding(@file.fetch("encoding", DEFAULT_ENCODING)),
          csv: CsvOptionsParser.new(@file["csv"], @errors).parse,
          xlsx: reader_options(@file["xlsx"], XLSX_KEYS, "file.xlsx")
        }
      end

      # Settings used by the HeaderMapper and the row pipeline.
      def headers
        {
          headers: boolean(@file.fetch("headers", true), "file.headers"),
          require_all_headers: boolean(@file.fetch("require_all_headers", false), "file.require_all_headers"),
          unknown_headers: one_of(@file.fetch("unknown_headers", DEFAULT_UNKNOWN_HEADERS), UNKNOWN_HEADERS, "file.unknown_headers"),
          extra_cells: one_of(@file.fetch("extra_cells", DEFAULT_EXTRA_CELLS), EXTRA_CELLS, "file.extra_cells")
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
    end
  end
end
