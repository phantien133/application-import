module ApplicationImport
  # Builds a new model record from row attributes.
  # Declared columns and transformer-generated keys: assigned when the model can set
  # them (setter).
  # Kept unknown headers (String keys): never assigned, unless assign_unknown (file.
  # unknown_headers: assign); then those naming a model attribute (header downcased,
  # spaces -> _, not the primary key nor a declared column) are assigned as read.
  module RecordBuilder
    module_function

    # generated: Symbol keys produced by transformers, assigned like declared columns.
    def build(model, attributes, columns, assign_unknown: false, generated: [])
      record = model.new
      record.assign_attributes(unknown(model, attributes, columns)) if assign_unknown
      record.assign_attributes(assignable(record, attributes, columns.map(&:key) | generated))
      record
    end

    def assignable(record, attributes, keys)
      keys.each_with_object({}) do |key, assignable|
        assignable[key] = attributes[key] if attributes.key?(key) && record.respond_to?("#{key}=")
      end
    end

    def unknown(model, attributes, columns)
      declared = columns.map { |column| column.key.to_s }
      attributes.each_with_object({}) do |(key, value), unknown|
        next unless key.is_a?(String)

        name = attribute_for(model, key)
        unknown[name] = value if name && declared.exclude?(name)
      end
    end

    # The model attribute a header names, or nil (primary key excluded). Uses
    # attribute_types (columns and attribute API attributes).
    def attribute_for(model, header)
      name = header.to_s.strip.downcase.gsub(/\s+/, "_")
      name if name != model.primary_key && model.attribute_types.key?(name)
    end
  end
end
