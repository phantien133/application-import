FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@#{Faker::Internet.domain_name}" }
    name { Faker::Name.name }
    age { Faker::Number.between(from: 18, to: 80) }
    balance { Faker::Number.decimal(l_digits: 4, r_digits: 2) }
    active { true }
    phone { Faker::Number.number(digits: 10).to_s }
    role { "member" }
    nickname { Faker::Internet.username(specifier: 3..20) }
    created_on { Faker::Date.backward(days: 365) }
    last_login_at { Faker::Time.backward(days: 30) }

    trait :admin do
      role { "admin" }
    end

    trait :inactive do
      active { false }
    end
  end
end
