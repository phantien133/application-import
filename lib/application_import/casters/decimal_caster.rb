module ApplicationImport
  module Casters
    # BigDecimal(value).
    class DecimalCaster < Base
      def call(value)
        return value if value.is_a?(BigDecimal)

        BigDecimal(value.is_a?(::Float) ? value.to_s : value.to_s.strip)
      end

      def type_name
        "a number"
      end
    end
  end
end
