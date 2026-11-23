module ApplicationImport
  module Errors
    class RowsError < Error
      attr_reader :code, :lines, :columns

      def initialize(message = nil, lines:, columns: [], code: :rows_conflict)
        lines = Array(lines)
        unless lines.any? && lines.all? { |line| line.is_a?(Integer) && line >= 1 }
          raise ArgumentError, "lines must be Integers >= 1, got #{lines.inspect}"
        end

        super(message)
        @code = code.to_sym
        @lines = lines
        @columns = Array(columns).map(&:to_s)
      end
    end
  end
end
