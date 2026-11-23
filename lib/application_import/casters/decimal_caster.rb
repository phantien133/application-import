module ApplicationImport
  module Casters
    # BigDecimal(value); NaN and Infinity are rejected (they pass every min / max).
    # decimal_separator / thousands_separator (column or file.numbers): see
    # LocalizedNumber.
    class DecimalCaster < Base
      include LocalizedNumber

      def call(value)
        decimal = value.is_a?(BigDecimal) ? value : parse(value)
        decimal.finite? ? decimal : invalid!
      end

      def type_name
        "a number"
      end

      private

      def parse(value)
        value.is_a?(::Float) ? BigDecimal(value.to_s) : BigDecimal(localized(value.to_s.strip))
      end
    end
  end
end
