module ApplicationImport
  module Errors
    class RowError < Error
      attr_reader :code, :line, :column

      def initialize(message = nil, line:, column: nil, code: :invalid_row)
        super(message)
        @code = code
        @line = line
        @column = column&.to_s
      end
    end
  end
end
