module ApplicationImport
  module Casters
    # Integer(value, 10): "1.5", "1e3", "0x1" are rejected. thousands_separator (column
    # or file.numbers): see LocalizedNumber.
    class IntegerCaster < Base
      include LocalizedNumber

      def call(value)
        value.is_a?(::Integer) ? value : Integer(localized(value.to_s.strip, fraction: false), 10)
      end

      def type_name
        "an integer"
      end
    end
  end
end
