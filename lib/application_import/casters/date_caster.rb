module ApplicationImport
  module Casters
    # Date: strict date_format, else ISO 8601, else Date.parse (see Temporal).
    class DateCaster < Base
      include Temporal

      def call(value)
        return value.to_date if value.is_a?(Date) || value.is_a?(Time)

        text = value.to_s.strip
        return Date.strptime(strict(text, date_format), date_format) if date_format

        iso_or_lenient("Date.parse") { Date.iso8601(text) } || Date.parse(full_date(text))
      end

      def type_name
        "a date"
      end
    end
  end
end
