module ApplicationImport
  # A data row after header mapping.
  # line: physical line in the file; attributes: column key => cell value (plus kept
  # unknown headers); raw: the cell values as read.
  Row = Data.define(:line, :attributes, :raw)
end
