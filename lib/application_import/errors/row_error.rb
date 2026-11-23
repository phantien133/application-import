module ApplicationImport
  module Errors
    class RowError < Error
      attr_reader :code, :line, :column

      def initialize(message = nil, line:, column: nil, code: :invalid_row)
        raise ArgumentError, "line must be an Integer >= 1, got #{line.inspect}" unless line.is_a?(Integer) && line >= 1

        super(message)
        @code = code.to_sym
        @line = line
        @column = column&.to_s
      end
    end
  end
end
