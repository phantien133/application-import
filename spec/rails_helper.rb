require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

# Shared helpers, matchers and configuration.
Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

# Keep the test schema in sync with db/schema.rb.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]

  # Wrap each example in a transaction that is rolled back afterwards.
  config.use_transactional_fixtures = true

  # Infer `type:` (model, request, system, ...) from the spec's directory.
  config.infer_spec_type_from_file_location!

  # freeze_time / travel_to
  config.include ActiveSupport::Testing::TimeHelpers

  # Hide Rails gem frames from backtraces.
  config.filter_rails_from_backtrace!
end
