module ApplicationImport
  module Casters
    # Shared by the date and datetime casters.
    # date_format set: strict strptime, the whole value must match (strptime itself
    # ignores trailing characters). Not set: ISO 8601, else a lenient parser that needs
    # an explicit year, month and day, with a warning once per column per run.
    module Temporal
      private

      def date_format
        column.options[:date_format]
      end

      def strict(text, format)
        parts = Date._strptime(text, format)
        raise ArgumentError, "does not match #{format}" if parts.nil? || parts.key?(:leftover)

        text
      end

      def iso_or_lenient(parser)
        yield
      rescue ArgumentError
        warn_lenient(parser)
        nil
      end

      def full_date(text)
        parts = Date._parse(text)
        raise ArgumentError, "not a full date" unless parts.values_at(:year, :mon, :mday).all?

        text
      end

      def warn_lenient(parser)
        return if @warned

        @warned = true
        warn("column #{column.key} (#{column.header}) has no date_format and a value is not ISO 8601: " \
             "parsing with #{parser}, ambiguous values such as 01/02/2026 may be misread; set date_format")
      end
    end
  end
end
