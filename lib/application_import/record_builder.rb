module ApplicationImport
  # Builds a new model record from row attributes: only the declared column keys the
  # model can set are assigned, so attributes of kept unknown headers (String keys) can
  # never set arbitrary model attributes.
  module RecordBuilder
    module_function

    def build(model, attributes, columns)
      record = model.new
      record.assign_attributes(assignable(record, attributes, columns))
      record
    end

    def assignable(record, attributes, columns)
      columns.each_with_object({}) do |column, assignable|
        key = column.key
        assignable[key] = attributes[key] if attributes.key?(key) && record.respond_to?("#{key}=")
      end
    end
  end
end
