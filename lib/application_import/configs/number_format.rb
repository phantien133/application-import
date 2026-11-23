module ApplicationImport
  module Configs
    # Validates number separators (file.numbers, or decimal_separator /
    # thousands_separator on a column): one character each, not a digit or a sign, and
    # different from each other.
    module NumberFormat
      KEYS = %w[ decimal_separator thousands_separator ].freeze

      module_function

      # { decimal_separator:, thousands_separator: } with the given keys, or {}.
      def parse(options, path, errors)
        format = KEYS.each_with_object({}) do |key, parsed|
          next unless options.key?(key)

          parsed[key.to_sym] = separator(options[key], "#{path}.#{key}", errors)
        end.compact
        if format.size == 2 && format.values.uniq.size == 1
          errors << "#{path} decimal_separator and thousands_separator must differ"
        end
        format
      end

      def separator(value, path, errors)
        return value if value.is_a?(String) && value.length == 1 && !value.match?(/[\d+-]/)

        errors << "#{path} must be one character other than a digit or a sign"
        nil
      end
    end
  end
end
