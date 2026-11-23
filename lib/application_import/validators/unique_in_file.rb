module ApplicationImport
  module Validators
    # type: unique_in_file — rows stage: a row whose keys repeat an earlier row of the
    # file gets a :duplicate error (details: keys, first line).
    #   keys:           attribute keys forming the identity (required); with transformers
    #                   or a mapper, the names they produce. A key missing from the row's
    #                   attributes raises Errors::ConfigError (the run fails).
    #   case_sensitive: compare String values with case (default true)
    # Rows with a blank key value, and rows with an error that is not allowed (dropped or
    # about to be, e.g. under row_errors: all), are neither checked nor remembered, so
    # they cannot make a valid later row a duplicate.
    class UniqueInFile < RowsValidator
      def call(row, _result, _cache)
        check_keys(row)
        return if dropped?(row)

        values = key_values(row)
        return if values.nil?

        first = seen[values]
        return seen[values] = row if first.nil? || first.equal?(row) || first.skipped?

        duplicate!(row, first)
      end

      def duplicate!(row, first)
        row.add_error(code: :duplicate, column: keys.first, message: "#{key_headers} duplicates line #{first.line}",
          details: { keys:, line: first.line })
      end

      def keys
        options.fetch(:keys)
      end

      def case_sensitive?
        options.fetch(:case_sensitive, true)
      end

      private

      def dropped?(row)
        row.errors.any? { |error| definition.on_error.action_for(error.code) != :allow }
      end

      def check_keys(row)
        missing = keys.reject { |key| row.attributes.key?(key) }
        return if missing.empty?

        raise Errors::ConfigError, "#{definition.name}: unique_in_file keys not in the row attributes: #{missing.join(", ")} " \
                                   "(attributes: #{row.attributes.keys.join(", ")})"
      end

      # Rows already seen by this run's instance, by key values. A row skipped after it was
      # seen (by a later check) gives way: the next row with its key is not a duplicate.
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
