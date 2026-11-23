module ApplicationImport
  ErrorPolicy = Data.define(:default, :allow, :skip) do
    def initialize(default: :abort, allow: [], skip: [])
      super
    end

    def action_for(code)
      code = code&.to_sym
      return :allow if allow.include?(code)
      return :skip if skip.include?(code)

      default
    end
  end
end
