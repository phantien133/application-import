# Minimal ActiveModel record for specs that need validation errors without a
# database table. Uses the :activerecord i18n scope so messages match a real
# ActiveRecord model (e.g. "Validation failed: Name can't be blank").
class ValidatedRecord
  include ActiveModel::Validations

  attr_accessor :name

  validates :name, presence: true

  class << self
    def i18n_scope
      :activerecord
    end

    def invalid
      new.tap(&:validate)
    end

    def valid
      new.tap { |record| record.name = "ok" }.tap(&:validate)
    end
  end
end
