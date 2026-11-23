module ApplicationImport
  # Builds a new model record from row attributes.
  # Declared columns and transformer-generated keys: assigned when the model can set
  # them (setter).
  # Kept unknown headers (String keys): never assigned, unless `assign` (rules of
  # file.unknown_headers: assign, see Definition#assign_rules); then those naming a model
  # attribute (header downcased, spaces -> _, not the primary key nor a declared column)
  # and allowed by the rules are assigned as read:
  #   {}                 -> every such attribute
  #   { allow: [ ... ] } -> only these attributes
  #   { ignore: [ ... ] }-> all but these attributes
  module RecordBuilder
    module_function

    # generated: Symbol keys produced by transformers / the mapper, assigned like
    # declared columns. assign: nil (kept headers never assigned) or the assign rules.
    def build(model, attributes, columns, assign: nil, generated: [])
      record = model.new
      record.assign_attributes(unknown(model, attributes, columns, assign)) if assign
      record.assign_attributes(assignable(record, attributes, columns.map(&:key) | generated))
      record
    end

    def assignable(record, attributes, keys)
      keys.each_with_object({}) do |key, assignable|
        assignable[key] = attributes[key] if attributes.key?(key) && record.respond_to?("#{key}=")
      end
    end

    def unknown(model, attributes, columns, rules)
      declared = columns.map { |column| column.key.to_s }
      attributes.each_with_object({}) do |(key, value), unknown|
        next unless key.is_a?(String)

        name = assigned_attribute(model, key, rules)
        unknown[name] = value if name && declared.exclude?(name)
      end
    end

    # The model attribute a kept header is assigned to under the rules, or nil.
    def assigned_attribute(model, header, rules)
      name = attribute_for(model, header)
      name if name && allowed?(name, rules)
    end

    def allowed?(name, rules)
      return rules[:allow].include?(name) if rules[:allow]
      return rules[:ignore].exclude?(name) if rules[:ignore]

      true
    end

    # The model attribute a header names, or nil (primary key excluded). Uses
    # attribute_types (columns and attribute API attributes).
    def attribute_for(model, header)
      name = header.to_s.strip.downcase.gsub(/\s+/, "_")
      name if name != model.primary_key && model.attribute_types.key?(name)
    end
  end
end
