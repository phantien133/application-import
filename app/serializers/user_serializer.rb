class UserSerializer < ApplicationSerializer
  attributes :id, :email, :name, :age, :active, :phone, :role, :nickname, :label, :created_by_id

  attribute(:balance) { |user| decimal(user.balance) }
  attribute(:created_on) { |user| date(user.created_on) }
  attribute(:last_login_at) { |user| time(user.last_login_at) }
  attribute(:created_at) { |user| time(user.created_at) }
  attribute(:updated_at) { |user| time(user.updated_at) }
end
