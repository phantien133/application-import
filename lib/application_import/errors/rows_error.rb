module ApplicationImport
  module Errors
    class RowsError < Error
      attr_reader :code, :lines, :columns

      def initialize(message = nil, lines:, columns: [], code: :rows_conflict)
        super(message)
        @code = code
        @lines = Array(lines)
        @columns = Array(columns).map(&:to_s)
      end
    end
  end
end
