module ApplicationImport
  module Configs
    # Parses file.csv into options for CSV.new (see Readers::Csv).
    #
    # Validated options:
    #   col_sep, row_sep             -> non-empty strings
    #   quote_char                   -> one character
    #   col_sep, quote_char and row_sep must differ
    #   liberal_parsing              -> true / false
    #   strip                        -> true / false, or one character to strip (csv gem limit)
    #   skip_lines                   -> regexp (source string)
    #   max_field_size               -> integer >= 1
    # passthrough: a mapping handed to CSV.new as-is (keys symbolized, values NOT
    # validated), applied last so it overrides the options above. Meant for options
    # the csv gem supports but this parser does not know yet. Options that change the
    # row shape (headers, converters, ...) break Readers::Base: use at your own risk.
    # Encoding is not a CSV option here: it is file.encoding, handled by EncodingGate.
    class CsvOptionsParser
      include Checks

      PATH = "file.csv".freeze
      # Options the reader manages itself (row shape, header row, blank / skipped lines and
      # their line numbers) cannot be passed through.
      MANAGED = %i[ headers return_headers header_converters converters unconverted_fields skip_blanks skip_lines
        write_headers write_converters write_nil_value write_empty_value ].freeze

      SEPARATORS = %i[ col_sep quote_char row_sep ].freeze
      STRING_KEYS = %w[ col_sep quote_char row_sep ].freeze
      KEYS = (STRING_KEYS + %w[ liberal_parsing strip skip_lines max_field_size passthrough ]).freeze

      def initialize(config, errors)
        @config = config
        @errors = errors
      end

      def parse
        options = mapping(@config, PATH)
        check_keys(options, KEYS, PATH)
        parsed = options.slice(*KEYS).compact.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = parse_option(key, value, "#{PATH}.#{key}")
        end.compact
        check_separators(parsed)
        parsed
      end

      private

      PARSERS = {
        "col_sep" => :string, "row_sep" => :string, "quote_char" => :quote_char, "liberal_parsing" => :boolean,
        "strip" => :strip, "skip_lines" => :pattern, "max_field_size" => :integer, "passthrough" => :passthrough
      }.freeze

      def parse_option(key, value, path)
        send(PARSERS.fetch(key), value, path)
      end

      def passthrough(value, path)
        options = mapping(value, path).deep_symbolize_keys
        managed = options.keys & MANAGED
        add_error(path, "has options the reader manages: #{managed.join(", ")}") if managed.any?
        options.except(*MANAGED)
      end

      def quote_char(value, path)
        return value if value.is_a?(String) && value.length == 1

        add_error(path, "must be one character")
      end

      # CSV defaults: col_sep "," and quote_char '"'; row_sep auto (newlines).
      def check_separators(parsed)
        separators = { col_sep: ",", quote_char: '"' }.merge(parsed.slice(*SEPARATORS))
        separators.group_by(&:last).each_value do |pairs|
          add_error(PATH, "#{pairs.map(&:first).join(" and ")} must differ (#{pairs.first.last.inspect})") if pairs.size > 1
        end
      end

      def string(value, path)
        return value if value.is_a?(String) && !value.empty?

        add_error(path, "must be a non-empty string")
      end

      def strip(value, path)
        return value if [ true, false ].include?(value) || (value.is_a?(String) && value.length == 1)

        add_error(path, "must be true, false or a single character")
      end

      def pattern(value, path)
        return add_error(path, "must be a regexp string") unless value.is_a?(String) && !value.empty?

        regexp(value, path)
      end
    end
  end
end
