module ApplicationImport
  module Readers
    # CSV reader. The content first passes the EncodingGate (BOM, file.encoding,
    # UTF-8); file.csv options (see Configs::CsvOptionsParser) go to CSV.new, with
    # file.csv.passthrough merged last, unvalidated.
    #
    # skip_lines is applied here, not by CSV.new, so skipped lines still count
    # towards line numbers: a record whose raw text matches is dropped. A String is
    # matched literally, like CSV does.
    # Raises FileError malformed_csv, plus the Base and EncodingGate errors.
    class Csv < Base
      private

      def each_record
        options = parser_options
        skip = skip_pattern(options.delete(:skip_lines))
        csv = ::CSV.new(content, **options)
        line = 1
        while (values = csv.shift)
          yield line, values unless skip&.match?(csv.line)
          line += lines_in(csv.line)
        end
      rescue ::CSV::MalformedCSVError => e
        raise Errors::FileError.new("malformed CSV: #{e.message}", code: :malformed_csv)
      end

      def parser_options
        options = definition.file[:csv]
        passthrough = options[:passthrough]
        return options.dup unless passthrough

        debug("passing unvalidated CSV options: #{passthrough.keys.join(", ")}")
        options.except(:passthrough).merge(passthrough)
      end

      def skip_pattern(value)
        value.is_a?(String) ? Regexp.new(Regexp.escape(value)) : value
      end

      def content
        @content ||= EncodingGate.new(definition, logger:).call(source).content
      end

      # Physical lines consumed by one record, quoted line breaks included.
      def lines_in(raw)
        raw.count("\n") + (raw.end_with?("\n") ? 0 : 1)
      end
    end
  end
end
