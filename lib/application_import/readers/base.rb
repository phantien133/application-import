module ApplicationImport
  module Readers
    # Shared reading rules; a format reader only implements #each_record, yielding
    # (line, values) for every record of the file in order, blank ones included.
    #
    # file.headers (default true):
    #   true  -> the first non-blank record is the header row, exposed by #headers
    #   false -> every record is data; #headers are the definition's column headers in
    #            definition order, so cells map to columns by position (RawRow#to_h)
    # #on_headers registers a callback called with #headers once known: right after the
    # header row, or before the first record without one (even for an empty file).
    # Blank records (no cell with content) are skipped.
    # Raises FileError empty_file (no header / no data rows). File size is bounded by
    # file.max_size (FileChecker), not by a row count.
    class Base
      include Enumerable
      include Logging

      attr_reader :definition, :source

      def initialize(definition, source, logger: ApplicationImport.logger)
        @definition = definition
        @source = source
        @logger = logger
      end

      def headers?
        definition.file.fetch(:headers, true)
      end

      # Header names as read (stripped), known once the first record has been read;
      # without a header row, the column headers.
      def headers
        headers? ? @headers : definition.columns.map(&:header)
      end

      def on_headers(&block)
        @on_headers = block
        self
      end

      def each(&)
        return enum_for(:each) unless block_given?

        @headers = nil
        @on_headers&.call(headers) unless headers?
        count = read_rows(&)
        check_not_empty(count)
        self
      end

      private

      def each_record
        raise NotImplementedError, "#{self.class.name}#each_record"
      end

      def read_rows
        count = 0
        each_record do |line, values|
          next if blank?(values) || read_header(values)

          count += 1
          yield RawRow.new(line:, values:)
        end
        count
      end

      def read_header(values)
        return false unless headers? && @headers.nil?

        @headers = values.map { |value| value.to_s.strip }
        @on_headers&.call(@headers)
        true
      end

      def blank?(values)
        values.all? { |value| value.nil? || value.to_s.strip.empty? }
      end

      def check_not_empty(count)
        return if count.positive?

        message = (headers? && @headers.nil?) ? "file has no header row" : "file has no data rows"
        raise Errors::FileError.new(message, code: :empty_file)
      end
    end
  end
end
