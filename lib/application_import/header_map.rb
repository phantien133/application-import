module ApplicationImport
  # Maps the cells of a data row to attributes, built by HeaderMapper.
  #   indexes: cell index => attribute key (column Symbol, or header String for a kept
  #            unknown header)
  #   width:   cells covered by the headers (header row size, or the column count
  #            without header row); nil when every cell is kept
  #   blank_indexes: positions of blank headers: their cells belong to no attribute and
  #            count as extra cells, like cells beyond the width
  #   keep_extra_from: without a header row and unknown_headers keep / assign, cells
  #            from this index on are kept as "column_<n>" (1-based)
  # Every column key is present in the attributes, nil when its header is missing.
  HeaderMap = Data.define(:column_keys, :indexes, :width, :keep_extra_from, :blank_indexes) do
    def initialize(column_keys:, indexes:, width: nil, keep_extra_from: nil, blank_indexes: [])
      super
    end

    def attributes(values)
      attributes = column_keys.index_with(nil)
      indexes.each { |index, key| attributes[key] = values[index] }
      keep_extra(values, attributes) if keep_extra_from
      attributes
    end

    # Non-blank cells beyond the headers or under a blank header, as [ index, value ]
    # pairs (they stay in the row's raw values).
    def extra_cells(values)
      return [] if width.nil?

      extra = blank_indexes.map { |index| [ index, values[index] ] } + values.each_with_index.drop(width).map(&:reverse)
      extra.reject { |_, value| value.nil? || value.to_s.strip.empty? }
    end

    private

    def keep_extra(values, attributes)
      values.each_with_index.drop(keep_extra_from).each { |value, index| attributes["column_#{index + 1}"] = value }
    end
  end
end
