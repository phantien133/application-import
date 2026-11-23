module ApplicationImport
  module Casters
    # Number separators for the integer and decimal casters: the column's
    # decimal_separator / thousands_separator, else file.numbers. When any is set the
    # text must match strictly (thousands in groups of three digits: with "." as the
    # thousands separator "1.5" is rejected, not read as 15) and is turned into
    # Ruby's format; otherwise the value is parsed as before.
    module LocalizedNumber
      private

      def number_format
        @number_format ||= (definition.file[:numbers] || {}).merge(column.options.slice(:decimal_separator, :thousands_separator))
      end

      # Ruby's Integer() / BigDecimal() accept "1_000": a file never means that.
      def localized(text, fraction: true)
        raise ArgumentError, "not a number" if text.include?("_")

        format = number_format
        return text if format.empty?

        raise ArgumentError, "not a number in the configured format" unless number_pattern(fraction).match?(text)

        thousands = format[:thousands_separator]
        text = text.delete(thousands) if thousands
        text.tr(format.fetch(:decimal_separator, "."), ".")
      end

      def number_pattern(fraction)
        (@number_patterns ||= {})[fraction] ||= begin
          thousands = number_format[:thousands_separator]
          integer = thousands ? "\\d{1,3}(?:#{Regexp.escape(thousands)}\\d{3})+|\\d+" : "\\d+"
          decimal = fraction ? "(?:#{Regexp.escape(number_format.fetch(:decimal_separator, "."))}\\d+)?" : ""
          Regexp.new("\\A[+-]?(?:#{integer})#{decimal}\\z")
        end
      end
    end
  end
end
