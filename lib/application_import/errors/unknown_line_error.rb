module ApplicationImport
  module Errors
    # A RowError / RowsError pointed at a line where no data row starts (header, blank or
    # skipped line, inside a multi-line record, a line computed from an index...): a bug
    # in the validator, transformer or handler that raised it, never in the file.
    class UnknownLineError < Error
      attr_reader :line, :source

      def initialize(line:, source: nil)
        @line = line
        @source = source
        super("no data row starts on line #{line}#{" (raised by #{source})" if source}; use row.line")
      end
    end
  end
end
