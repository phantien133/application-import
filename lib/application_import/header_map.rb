module ApplicationImport
  # Maps the cells of a data row to attributes, built by HeaderMapper.
  #   indexes: cell index => attribute key (column Symbol, or header String for a kept
  #            unknown header)
  #   keep_extra_from: without a header row and unknown_headers: keep, cells from this
  #            index on are kept as "column_<n>" (1-based)
  # Every column key is present in the attributes, nil when its header is missing.
  HeaderMap = Data.define(:column_keys, :indexes, :keep_extra_from) do
    def initialize(column_keys:, indexes:, keep_extra_from: nil)
      super
    end

    def attributes(values)
      attributes = column_keys.index_with(nil)
      indexes.each { |index, key| attributes[key] = values[index] }
      keep_extra(values, attributes) if keep_extra_from
      attributes
    end

    private

    def keep_extra(values, attributes)
      values.each_with_index.drop(keep_extra_from).each { |value, index| attributes["column_#{index + 1}"] = value }
    end
  end
end
