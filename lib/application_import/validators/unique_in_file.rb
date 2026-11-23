module ApplicationImport
  module Validators
    # type: unique_in_file — rows stage: a row whose keys repeat an earlier row of the
    # file gets a :duplicate error (details: keys, first line).
    #   keys:           column keys forming the identity (required)
    #   case_sensitive: compare String values with case (default true)
    # Rows with a blank key value are not checked. Rows that stopped before this check
    # (errors under row_errors: first) are not remembered.
    class UniqueInFile < RowsValidator
      def call(row, _result, _cache)
        values = key_values(row)
        return if values.nil?

        first = seen[values] ||= row.line
        return if first == row.line

        row.add_error(code: :duplicate, column: keys.first, message: "#{key_headers} duplicates line #{first}",
          details: { keys:, line: first })
      end

      def keys
        options.fetch(:keys)
      end

      def case_sensitive?
        options.fetch(:case_sensitive, true)
      end

      private

      # Lines already seen by this run's instance, by key values.
      def seen
        @seen ||= {}
      end

      def key_values(row)
        values = keys.map { |key| normalize(row.attributes[key]) }
        values unless values.any? { |value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
      end

      def normalize(value)
        value = value.strip if value.is_a?(String)
        (value.is_a?(String) && !case_sensitive?) ? value.downcase : value
      end

      def key_headers
        @key_headers ||= definition.columns.select { |column| keys.include?(column.key) }.map(&:header).join(", ")
      end
    end
  end
end
