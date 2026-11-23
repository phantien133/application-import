module ApplicationImport
  module Readers
    # CSV reader, streaming: the source passes the EncodingGate chunk by chunk into
    # a UTF-8 tempfile, which CSV then parses record by record.
    # file.csv options (see Configs::CsvOptionsParser) go to CSV.new, with
    # file.csv.passthrough merged last, unvalidated.
    #
    # Line endings: unless row_sep is configured, CRLF and lone CR are turned into LF
    # first, so files mixing \n, \r\n and \r parse (quoted values get LF too).
    # skip_lines is applied by SkipLines on the raw lines before the parser (not by
    # CSV.new): only lines starting a record, blanked so line numbers stay right.
    # max_field_size defaults to DEFAULT_MAX_FIELD_SIZE (1 MiB characters).
    # Raises FileError malformed_csv, plus the Base and EncodingGate errors.
    class Csv < Base
      private

      def each_record(&)
        options = parser_options
        skip = options.delete(:skip_lines)
        filter = skip && SkipLines.new(skip, options.fetch(:quote_char, '"'))
        gate = EncodingGate.new(definition, logger:, normalize_newlines: !options.key?(:row_sep), line_filter: filter)
        gate.call(source) { |text| parse(text.io, options, &) }
      end

      def parse(io, options)
        csv = ::CSV.new(io, **options)
        line = 1
        while (values = csv.shift)
          yield line, values
          line += lines_in(csv.line)
        end
      rescue ::CSV::MalformedCSVError => e
        raise Errors::FileError.new("malformed CSV: #{e.message}", code: :malformed_csv)
      end

      # file.csv options, max_field_size defaulting to DEFAULT_MAX_FIELD_SIZE, then the
      # passthrough options on top.
      def parser_options
        options = { max_field_size: Constants::DEFAULT_MAX_FIELD_SIZE }.merge(definition.file[:csv])
        passthrough = options.delete(:passthrough)
        return options unless passthrough

        debug("passing unvalidated CSV options: #{passthrough.keys.join(", ")}")
        options.merge(passthrough)
      end

      # Physical lines consumed by one record, quoted line breaks included.
      def lines_in(raw)
        raw.count("\n") + (raw.end_with?("\n") ? 0 : 1)
      end
    end
  end
end
