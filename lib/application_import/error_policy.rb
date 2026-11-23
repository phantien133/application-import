module ApplicationImport
  # What to do with row errors (file errors always abort):
  #   default / allow / skip -> action per error code (abort | skip | allow)
  #   row_errors             -> :first: a row stops at the first check that reports errors
  #                             (a check may report several), then the action applies;
  #                             :all: every check of the row runs and all its errors are
  #                             collected before the action applies
  ErrorPolicy = Data.define(:default, :allow, :skip, :row_errors) do
    def initialize(default: :abort, allow: [], skip: [], row_errors: :first)
      super
    end

    def action_for(code)
      code = code&.to_sym
      return :allow if allow.include?(code)
      return :skip if skip.include?(code)

      default
    end

    def collect_all?
      row_errors == :all
    end
  end
end
