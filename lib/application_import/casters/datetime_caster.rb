module ApplicationImport
  module Casters
    # Time in Time.zone: strict date_format, else ISO 8601, else Time.zone.parse
    # (see Temporal).
    class DatetimeCaster < Base
      include Temporal

      def call(value)
        return value.in_time_zone if value.is_a?(Time) || value.is_a?(Date)

        text = value.to_s.strip
        date_format ? Time.zone.strptime(strict(text, date_format), date_format) : parse(text)
      end

      def type_name
        "a date and time"
      end

      private

      def parse(text)
        iso_or_lenient("Time.zone.parse") { Time.zone.iso8601(text) } ||
          Time.zone.parse(full_date(text)) || raise(ArgumentError, "no date")
      end
    end
  end
end
