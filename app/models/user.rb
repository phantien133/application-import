class User < ApplicationRecord
  ROLES = %w[ admin member guest ].freeze

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :role, with: ->(role) { role.strip.downcase }

  validates :email, presence: true, length: { maximum: 255 }, format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: { case_sensitive: false }
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :age, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 150 },
    allow_nil: true
  validates :balance, numericality: { greater_than_or_equal_to: 0 }
  validates :active, inclusion: { in: [ true, false ] }
  validates :role, inclusion: { in: ROLES }
  validates :phone, length: { maximum: 30 }, allow_blank: true
  validates :nickname, length: { maximum: 50 }, allow_blank: true
end
