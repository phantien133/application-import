module ApplicationImport
  # Checks the file headers against the definition's columns and builds the HeaderMap.
  #
  # With a header row (file.headers: true), headers may come in any order. A header
  # matches a column by its header or one of its aliases (ignoring case and surrounding /
  # repeated whitespace), else by the column's header_pattern regexps (case-insensitive,
  # against the stripped header); names win over patterns:
  #   - a header matching the patterns of several
  #     columns                                   -> file error ambiguous_headers
  #   - a required column without header (every
  #     column with file.require_all_headers)     -> file error missing_headers
  #   - an optional column without header         -> its attribute is nil (logged)
  #   - two headers for one column, or repeated
  #     kept unknown headers                      -> file error duplicate_headers
  #   - unknown headers, per file.unknown_headers:
  #       skip (default) -> ignored (logged)
  #       keep           -> passed through as attributes keyed by the header String: never
  #                         assigned to the record; available to transformers, the mapper
  #                         and the handler to map explicitly, and in raw output
  #       assign         -> like keep, and the record builder assigns those matching a
  #                         model attribute (header downcased, spaces -> _) straight to
  #                         the record, without cast or rules, limited by file.assign
  #                         allow / ignore (none: all, warned at load); the others are
  #                         warned about (needs output.model)
  #       reject         -> file error unknown_headers
  #     blank headers are ignored (warned) by keep, assign and reject; cells under a
  #     blank header count as extra cells (file.extra_cells)
  # Exact headers (every column, nothing else): require_all_headers: true +
  # unknown_headers: reject.
  # Without a header row (file.headers: false), cells map to columns by position; with
  # keep / assign, the extra cells are kept as "column_<n>".
  # Errors are added to the result (all of them); the caller halts on file errors.
  class HeaderMapper
    include Logging

    attr_reader :definition

    class << self
      # Unicode spaces (NBSP from spreadsheets, ...) and zero-width marks count as spaces.
      def normalize(header)
        header.to_s.gsub(Readers::Base::SPACES, " ").strip.downcase
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

    def require_all_headers?
      definition.file[:require_all_headers] == true
    end

    def keep_unknown?
      %i[ keep assign ].include?(definition.file[:unknown_headers])
    end

    def assign_unknown?
      definition.file[:unknown_headers] == :assign
    end

    def unknown_headers
      definition.file[:unknown_headers] || :skip
    end

    def column_keys
      definition.columns.map(&:key)
    end

    def model
      definition.output[:model]
    end

    # Exposes the private log helpers to the Matcher.
    def log(level, message)
      send(level, message)
    end

    private

    def positional_map
      indexes = column_keys.each_with_index.to_h { |key, index| [ index, key ] }
      debug { "no header row: cells mapped by position to #{column_keys.join(", ")}" }
      return HeaderMap.new(column_keys:, indexes:, keep_extra_from: column_keys.size) if keep_unknown?

      HeaderMap.new(column_keys:, indexes:, width: column_keys.size)
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
        @mapper.log(:debug, "headers mapped: #{@indexes.map { |index, key| "#{@headers[index].to_s.strip} -> #{key}" }.join(", ")}")
        HeaderMap.new(column_keys: @mapper.column_keys, indexes: @indexes, width: @headers.size, blank_indexes:)
      end

      private

      def blank_indexes
        @headers.each_index.select { |index| @headers[index].to_s.strip.empty? }
      end

      def match(header, index)
        column = lookup[HeaderMapper.normalize(header)] || pattern_match(header)
        return @unknown << [ header, index ] if column.nil?
        return if column == :ambiguous
        return duplicate(header, column.header) if @matched.key?(column.key)

        @matched[column.key] = header
        @indexes[index] = column.key
      end

      def pattern_match(header)
        columns = patterned.select { |column| column.header_patterns.any? { |pattern| pattern.match?(header) } }
        return columns.first if columns.size <= 1

        names = columns.map(&:header)
        @result.add_file_error(:ambiguous_headers, "header #{header.inspect} matches several columns: #{names.join(", ")}",
          details: { header:, columns: names })
        :ambiguous
      end

      def patterned
        @patterned ||= @mapper.definition.columns.select { |column| column.header_patterns.any? }
      end

      def lookup
        @lookup ||= @mapper.definition.columns.each_with_object({}) do |column, lookup|
          column.headers.each { |header| lookup[HeaderMapper.normalize(header)] = column }
        end
      end

      def check_missing
        required, optional = missing_columns.partition { |column| must_have_header?(column) }
        @mapper.log(:info, "optional headers not found: #{optional.map(&:header).join(", ")}") if optional.any?
        report_missing(required.map(&:header)) if required.any?
      end

      def missing_columns
        @mapper.definition.columns.reject { |column| @matched.key?(column.key) }
      end

      def must_have_header?(column)
        @mapper.require_all_headers? || column.required?
      end

      def report_missing(names)
        @result.add_file_error(:missing_headers, "missing required headers: #{names.join(", ")}", details: { headers: names })
      end

      def handle_unknown
        return if @unknown.empty?

        case @mapper.unknown_headers
        when :keep then keep_unknown(named_unknown)
        when :assign then assign_unknown(named_unknown)
        when :reject then reject_unknown(named_unknown)
        else @mapper.log(:info, "ignoring unknown headers: #{@unknown.map(&:first).join(", ")}")
        end
      end

      def named_unknown
        blank, named = @unknown.partition { |header, _| header.empty? }
        @mapper.log(:warn, "ignoring #{blank.size} blank headers") if blank.any?
        named
      end

      def reject_unknown(named)
        return if named.empty?

        names = named.map(&:first)
        @result.add_file_error(:unknown_headers, "unknown headers: #{names.join(", ")}", details: { headers: names })
      end

      # Kept like keep; tells which headers will reach the record and warns about the rest.
      def assign_unknown(named)
        keep_unknown(named)
        rules = @mapper.definition.assign_rules
        assigned, others = named.map(&:first).partition { |header| RecordBuilder.assigned_attribute(@mapper.model, header, rules) }
        log_assign(assigned, others)
      end

      def log_assign(assigned, others)
        model = @mapper.model.name
        @mapper.log(:info, "assigning unknown headers to #{model} as they are: #{assigned.join(", ")}") if assigned.any?
        return if others.empty?

        @mapper.log(:warn, "unknown headers not assigned to #{model} (no such attribute, or not allowed by file.assign), " \
                           "kept: #{others.join(", ")}")
      end

      # Repeated unknown headers are compared like column headers (case, spaces).
      def keep_unknown(named)
        kept = {}
        named.each do |header, index|
          first = kept[HeaderMapper.normalize(header)]
          next duplicate(header, first) if first

          kept[HeaderMapper.normalize(header)] = header
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
