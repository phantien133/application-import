module ApplicationImport
  module Casters
    # true/t/yes/y/1 and false/f/no/n/0, case-insensitive. Subclass and override
    # TRUE_VALUES / FALSE_VALUES (or #call) for other words.
    class BooleanCaster < Base
      TRUE_VALUES = %w[ true t yes y 1 ].freeze
      FALSE_VALUES = %w[ false f no n 0 ].freeze

      def call(value)
        return value if [ true, false ].include?(value)

        text = value.to_s.strip.downcase
        return true if self.class::TRUE_VALUES.include?(text)
        return false if self.class::FALSE_VALUES.include?(text)

        invalid!
      end

      def type_name
        "true or false"
      end
    end
  end
end
