RSpec.describe ApplicationImport do
  describe ".definition" do
    let(:definition) { instance_double(ApplicationImport::Definition) }

    before do
      described_class.clear_definitions!
      allow(ApplicationImport::Definition).to receive(:load).and_return(definition)
    end

    after { described_class.clear_definitions! }

    it "loads once and reuses the definition when caching is on" do
      allow(described_class).to receive(:cache_definitions?).and_return(true)

      expect([ described_class.definition(:users), described_class.definition("users") ]).to eq([ definition, definition ])
      expect(ApplicationImport::Definition).to have_received(:load).once
    end

    it "loads again after clear_definitions!" do
      allow(described_class).to receive(:cache_definitions?).and_return(true)
      described_class.definition(:users)
      described_class.clear_definitions!
      described_class.definition(:users)

      expect(ApplicationImport::Definition).to have_received(:load).twice
    end

    it "loads every time when caching is off" do
      allow(described_class).to receive(:cache_definitions?).and_return(false)
      2.times { described_class.definition(:users) }

      expect(ApplicationImport::Definition).to have_received(:load).twice
    end

    it "rejects invalid names before caching" do
      allow(described_class).to receive(:cache_definitions?).and_return(true)

      expect { described_class.definition("../users") }.to raise_error(ApplicationImport::Errors::ConfigError, /invalid import name/)
    end

    it "caches only when code reloading is disabled" do
      expect(described_class.cache_definitions?).to eq(!Rails.application.config.enable_reloading)
    end
  end

  describe ".run" do
    let(:runner_class) do
      stub_const("ApplicationImport::Runner", Class.new do
        attr_reader :args

        def initialize(*args, **kwargs)
          @args = [ args, kwargs ]
        end

        def call
          self
        end
      end)
    end
    let(:definition) { ApplicationImport::Definition.allocate }
    let(:source) { Object.new }

    before do
      runner_class
      built = source
      stub_const("ApplicationImport::Source", Module.new)
      ApplicationImport::Source.define_singleton_method(:build) { |_file, filename:| built if filename == "u.csv" }
    end

    it "runs the default Runner with the definition, source and context" do
      result = described_class.run(definition, "users.csv", filename: "u.csv", context: { user_id: 1 })

      expect(result).to be_a(runner_class)
      expect(result.args).to eq([ [ definition, source ], { context: { user_id: 1 } } ])
    end

    it "loads the definition when given a name" do
      allow(described_class).to receive(:definition).with(:users).and_return(definition)

      expect(described_class.run(:users, "users.csv", filename: "u.csv").args.first).to eq([ definition, source ])
    end

    it "uses a custom Runner subclass" do
      custom = stub_const("CustomRunner", Class.new(runner_class))

      expect(described_class.run(definition, "users.csv", filename: "u.csv", runner: "CustomRunner")).to be_a(custom)
    end

    it "raises InvalidRunnerError for a runner not inheriting Runner" do
      expect { described_class.run(definition, "users.csv", filename: "u.csv", runner: String) }
        .to raise_error(ApplicationImport::Errors::InvalidRunnerError, "String must inherit from ApplicationImport::Runner")
    end
  end
end
