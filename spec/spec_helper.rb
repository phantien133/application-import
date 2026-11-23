# Plain RSpec configuration (no Rails). Loaded by every spec via .rspec.
# Rails-specific setup lives in spec/rails_helper.rb.
# See https://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    # Stubbing a method that does not exist on the real object is an error.
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # `fit` / `fdescribe` / `focus: true` run only the focused examples.
  config.filter_run_when_matching :focus

  # Enables `rspec --only-failures` and `--next-failure`.
  config.example_status_persistence_file_path = "tmp/rspec_examples.txt"

  # Only the `RSpec.describe` / `expect` syntax, no monkey patching.
  config.disable_monkey_patching!

  # Detailed output when running a single file.
  config.default_formatter = "doc" if config.files_to_run.one?

  # Report the 10 slowest examples.
  config.profile_examples = 10

  # Random order surfaces order dependencies; reproduce with `--seed`.
  config.order = :random
  Kernel.srand config.seed
end
