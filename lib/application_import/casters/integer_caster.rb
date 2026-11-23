module ApplicationImport
  module Casters
    # Integer(value, 10): "1.5", "1e3", "0x1" are rejected.
    class IntegerCaster < Base
      def call(value)
        value.is_a?(::Integer) ? value : Integer(value.to_s.strip, 10)
      end

      def type_name
        "an integer"
      end
    end
  end
end
