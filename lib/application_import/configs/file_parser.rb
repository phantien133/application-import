module ApplicationImport
  module Configs
    # Parses the definition's file section.
    class FileParser
      include Checks
      include Constants

      KEYS = %w[ checker formats name_pattern max_size format reader encoding headers require_all_headers
        unknown_headers assign extra_cells numbers csv xlsx ].freeze
      XLSX_KEYS = %w[ sheet ].freeze
      HOST_ALIASES = %w[ locale external filesystem internal ].freeze

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
          extra_cells: one_of(@file.fetch("extra_cells", DEFAULT_EXTRA_CELLS), EXTRA_CELLS, "file.extra_cells"),
          assign: assign_rules,
          numbers: numbers
        }
      end

      # Default number separators of integer / decimal columns (a column's own win).
      def numbers
        options = mapping(@file["numbers"], "file.numbers")
        check_keys(options, NumberFormat::KEYS, "file.numbers")
        NumberFormat.parse(options, "file.numbers", @errors).presence
      end

      # file.assign (with unknown_headers: assign): { allow: [...] } or { ignore: [...] },
      # attribute names; nil when absent (every matching attribute, warned at load).
      def assign_rules
        return unless @file.key?("assign")

        rules = mapping(@file["assign"], "file.assign")
        check_keys(rules, %w[ allow ignore ], "file.assign")
        return add_error("file.assign", "needs exactly one of allow, ignore") unless rules.keys.intersection(%w[ allow ignore ]).one?

        key = rules.key?("allow") ? :allow : :ignore
        { key => names(rules[key.to_s], "file.assign.#{key}").map { |name| name.strip.downcase } }
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

      # A real encoding that can be converted to UTF-8 (UTF-16 / UTF-32 without byte
      # order need a BOM in the file); host-dependent aliases are rejected.
      def encoding(value)
        return add_error("file.encoding", "must name an encoding, not #{value}") if HOST_ALIASES.include?(value.to_s.downcase)

        found = Encoding.find(value.to_s)
        Readers::EncodingGate.convertible?(found) ? found.name : add_error("file.encoding", "cannot be converted to UTF-8: #{value}")
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
