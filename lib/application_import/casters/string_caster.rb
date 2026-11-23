module ApplicationImport
  module Casters
    # The value as read.
    class StringCaster < Base
      def call(value)
        value.to_s
      end

      def type_name
        "text"
      end
    end
  end
end
