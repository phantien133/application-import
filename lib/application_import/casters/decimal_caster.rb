module ApplicationImport
  module Casters
    # BigDecimal(value); NaN and Infinity are rejected (they pass every min / max).
    class DecimalCaster < Base
      def call(value)
        decimal = value.is_a?(BigDecimal) ? value : parse(value)
        decimal.finite? ? decimal : invalid!
      end

      def type_name
        "a number"
      end

      private

      def parse(value)
        BigDecimal(value.is_a?(::Float) ? value.to_s : value.to_s.strip)
      end
    end
  end
end
