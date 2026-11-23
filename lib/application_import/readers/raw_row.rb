module ApplicationImport
  module Readers
    # One data record as read from the file, before casting.
    # line:   physical line where the record starts (header = 1); a quoted field
    #         spanning several lines still reports its first line.
    # values: cell values in file order (nil for empty cells).
    RawRow = Data.define(:line, :values) do
      # Pairs each header with the value at the same position; missing cells are nil,
      # extra cells are dropped.
      def to_h(headers)
        headers.each_with_index.to_h { |header, index| [ header, values[index] ] }
      end
    end
  end
end
