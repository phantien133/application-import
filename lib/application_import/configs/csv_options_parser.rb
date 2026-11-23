module ApplicationImport
  module Configs
    # Parses file.csv into options for CSV.new (see Readers::Csv).
    #
    # Validated options:
    #   col_sep, quote_char, row_sep -> non-empty strings
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
      STRING_KEYS = %w[ col_sep quote_char row_sep ].freeze
      KEYS = (STRING_KEYS + %w[ liberal_parsing strip skip_lines max_field_size passthrough ]).freeze

      def initialize(config, errors)
        @config = config
        @errors = errors
      end

      def parse
        options = mapping(@config, PATH)
        check_keys(options, KEYS, PATH)
        options.slice(*KEYS).compact.each_with_object({}) do |(key, value), parsed|
          parsed[key.to_sym] = parse_option(key, value, "#{PATH}.#{key}")
        end.compact
      end

      private

      def parse_option(key, value, path)
        case key
        when *STRING_KEYS then string(value, path)
        when "liberal_parsing" then boolean(value, path)
        when "strip" then strip(value, path)
        when "skip_lines" then pattern(value, path)
        when "max_field_size" then integer(value, path)
        when "passthrough" then mapping(value, path).deep_symbolize_keys
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
