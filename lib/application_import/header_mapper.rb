module ApplicationImport
  # Checks the file headers against the definition's columns and builds the HeaderMap.
  #
  # With a header row (file.headers: true), headers may come in any order. A header
  # matches a column by its header or one of its aliases, ignoring case and surrounding /
  # repeated whitespace:
  #   - a required column without header          -> file error missing_headers
  #   - an optional column without header         -> its attribute is nil (logged)
  #   - two headers for one column, or repeated
  #     kept unknown headers                      -> file error duplicate_headers
  #   - unknown headers, per file.unknown_headers:
  #       skip (default) -> ignored (logged)
  #       keep           -> passed through as attributes keyed by the header String
  #                         (blank ones are ignored)
  # Without a header row (file.headers: false), cells map to columns by position; with
  # keep, the extra cells are kept as "column_<n>".
  # Errors are added to the result (all of them); the caller halts on file errors.
  class HeaderMapper
    include Logging

    attr_reader :definition

    class << self
      def normalize(header)
        header.to_s.strip.gsub(/\s+/, " ").downcase
      end
    end

    def initialize(definition, logger: ApplicationImport.logger)
      @definition = definition
      @logger = logger
    end

    def call(headers, result)
      return positional_map unless definition.file.fetch(:headers, true)

      Matcher.new(self, headers, result).map
    end

    def keep_unknown?
      definition.file[:unknown_headers] == :keep
    end

    def column_keys
      definition.columns.map(&:key)
    end

    # Exposes the private log helpers to the Matcher.
    def log(level, message)
      send(level, message)
    end

    private

    def positional_map
      indexes = column_keys.each_with_index.to_h { |key, index| [ index, key ] }
      HeaderMap.new(column_keys:, indexes:, keep_extra_from: keep_unknown? ? column_keys.size : nil)
    end

    # One matching pass over the header row.
    class Matcher
      def initialize(mapper, headers, result)
        @mapper = mapper
        @headers = headers
        @result = result
        @indexes = {}
        @matched = {}
        @unknown = []
      end

      def map
        @headers.each_with_index { |header, index| match(header.to_s.strip, index) }
        check_missing
        handle_unknown
        HeaderMap.new(column_keys: @mapper.column_keys, indexes: @indexes)
      end

      private

      def match(header, index)
        column = lookup[HeaderMapper.normalize(header)]
        return @unknown << [ header, index ] unless column
        return duplicate(header, column.header) if @matched.key?(column.key)

        @matched[column.key] = header
        @indexes[index] = column.key
      end

      def lookup
        @lookup ||= @mapper.definition.columns.each_with_object({}) do |column, lookup|
          column.headers.each { |header| lookup[HeaderMapper.normalize(header)] = column }
        end
      end

      def check_missing
        missing = @mapper.definition.columns.reject { |column| @matched.key?(column.key) }
        required, optional = missing.partition(&:required?)
        @mapper.log(:info, "optional headers not found: #{optional.map(&:header).join(", ")}") if optional.any?
        return if required.empty?

        names = required.map(&:header)
        @result.add_file_error(:missing_headers, "missing required headers: #{names.join(", ")}", details: { headers: names })
      end

      def handle_unknown
        return if @unknown.empty?
        return keep_unknown if @mapper.keep_unknown?

        @mapper.log(:info, "ignoring unknown headers: #{@unknown.map(&:first).join(", ")}")
      end

      def keep_unknown
        blank, named = @unknown.partition { |header, _| header.empty? }
        @mapper.log(:warn, "ignoring #{blank.size} blank headers") if blank.any?
        named.each do |header, index|
          next duplicate(header, header) if @indexes.value?(header)

          @indexes[index] = header
        end
      end

      def duplicate(header, column_header)
        @result.add_file_error(:duplicate_headers, "header #{header.inspect} duplicates #{column_header.inspect}",
          details: { header:, column: column_header })
      end
    end
  end
end
