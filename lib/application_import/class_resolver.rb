module ApplicationImport
  module ClassResolver
    module_function

    def resolve!(name, base:, default: nil, error: Errors::InvalidClassError)
      return default if name.blank?

      base = constantize(base)
      klass = name.is_a?(Class) ? name : name.to_s.safe_constantize
      raise error.new("#{name} not found", klass: name, base:) unless klass
      raise error.new(klass:, base:) unless klass.is_a?(Class) && klass <= base

      klass
    end

    # An ActiveRecord model of the end user's: not ActiveRecord::Base itself nor an
    # abstract class (ApplicationRecord, ...), which have no table to write to.
    def resolve_model!(name, path:)
      model = resolve!(name, base: "ActiveRecord::Base")
      raise Errors::InvalidClassError.new("#{path} must be an application model", klass: model, base: ActiveRecord::Base) if internal_model?(model)
      return model if model.nil? || (model != ActiveRecord::Base && !model.abstract_class?)

      raise Errors::InvalidClassError.new("#{path} must be a concrete model, #{model.name} is abstract", klass: model,
        base: ActiveRecord::Base)
    end

    # Rails' own models (ActiveRecord::InternalMetadata, Active Storage, ...).
    def internal_model?(model)
      !model.nil? && model != ActiveRecord::Base && model.name.to_s.start_with?("ActiveRecord::", "ActiveStorage::", "ActionText::", "ActionMailbox::",
        "SolidQueue::", "SolidCable::")
    end

    def constantize(name)
      name.is_a?(Module) ? name : name.to_s.constantize
    end
  end
end
