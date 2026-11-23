module ApplicationImport
  # One reader per format, chosen by the definition's file.format (default csv).
  # A definition can bring its own reader with file.reader: any subclass of
  # Readers::Base (or of a built-in reader such as Readers::Csv). Contract:
  #   - #each yields RawRow(line:, values:) for data rows only, and #headers
  #     returns the header names (or column headers when file.headers is false);
  #   - read problems are raised as Errors::FileError.
  # Base fulfils it from #each_record (yield line, values per record), so a
  # subclass usually only overrides #each_record or a private hook of its parent.
  module Readers
    READERS = {
      csv: "ApplicationImport::Readers::Csv",
      xlsx: "ApplicationImport::Readers::Xlsx"
    }.freeze

    class << self
      def for(definition, source, logger: ApplicationImport.logger)
        definition.reader_class(source.extension).new(definition, source, logger:)
      end

      def reader_class(format)
        format = (format || Constants::DEFAULT_FORMAT).to_sym
        READERS.fetch(format) { raise Errors::ConfigError, "no reader for format #{format}" }.constantize
      end
    end
  end
end
