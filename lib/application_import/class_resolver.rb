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

    def constantize(name)
      name.is_a?(Module) ? name : name.to_s.constantize
    end
  end
end
