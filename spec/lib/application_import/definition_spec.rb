RSpec.describe ApplicationImport::Definition do
  let(:parsed) do
    {
      handler: ApplicationImport::Handler, file: { validator: ApplicationImport::FileValidator, max_rows: 100 },
      columns: [], validators: [], output: { mode: :raw }, on_error: ApplicationImport::ErrorPolicy.new
    }
  end

  before do
    result = parsed
    stub_const("ApplicationImport::Configs::DefinitionParser", Class.new do
      define_method(:initialize) { |_name, _config| nil }
      define_method(:parse) { result }
    end)
  end

  def build(**overrides)
    parsed.merge!(overrides)
    described_class.new("users", {})
  end

  describe "#initialize" do
    it "exposes the parsed config and freezes itself" do
      definition = build

      expect([ definition.name, definition.handler_class, definition.output, definition.on_error ])
        .to eq([ :users, ApplicationImport::Handler, { mode: :raw }, ApplicationImport::ErrorPolicy.new ])
      expect(definition).to be_frozen
    end
  end

  describe ".normalize_name" do
    it "accepts snake_case names as String or Symbol" do
      expect([ described_class.normalize_name("users"), described_class.normalize_name(:user_v2) ]).to eq(%i[ users user_v2 ])
    end

    it "rejects anything else" do
      [ nil, 1, "", "Users", "../users", "/etc/passwd", "users.yml", "a b" ].each do |name|
        expect { described_class.normalize_name(name) }
          .to raise_error(ApplicationImport::Errors::ConfigError, "invalid import name: #{name.inspect}")
      end
    end

    it "is used by .new" do
      expect { described_class.new(nil, {}) }.to raise_error(ApplicationImport::Errors::ConfigError, /invalid import name/)
    end
  end

  describe ".load" do
    let(:dir) { Pathname(Dir.mktmpdir) }

    before { allow(ApplicationImport).to receive(:configuration).and_return(double(config_path: dir)) }
    after { FileUtils.remove_entry(dir) }

    it "loads <config_path>/<name>.yml" do
      dir.join("users.yml").write("on_error: skip\n")

      expect(described_class.load(:users).name).to eq(:users)
    end

    it "rejects path traversal before touching the file system" do
      dir.join("secret.yml").write("on_error: skip\n")

      expect { described_class.load("../#{dir.basename}/secret") }
        .to raise_error(ApplicationImport::Errors::ConfigError, /invalid import name/)
    end

    it "raises ConfigError when the file is missing" do
      expect { described_class.load(:missing) }
        .to raise_error(ApplicationImport::Errors::ConfigError, /import config not found: .*missing\.yml/)
    end

    it "raises ConfigError on invalid YAML" do
      dir.join("broken.yml").write("columns: [\n")

      expect { described_class.load(:broken) }.to raise_error(ApplicationImport::Errors::ConfigError, /invalid YAML/)
    end

    it "raises ConfigError on YAML that is not safe to load" do
      dir.join("unsafe.yml").write("--- !ruby/object:Object {}\n")

      expect { described_class.load(:unsafe) }.to raise_error(ApplicationImport::Errors::ConfigError, /invalid YAML/)
    end
  end

  describe "class readers" do
    it "returns the classes resolved by the parser" do
      handler = stub_const("UsersHandler", Class.new(ApplicationImport::Handler))
      validator = stub_const("UsersFileValidator", Class.new(ApplicationImport::FileValidator))
      definition = build(handler:, file: { validator:, max_rows: 100 })

      expect([ definition.handler_class, definition.file_validator_class ]).to eq([ handler, validator ])
    end
  end

  describe "#max_rows" do
    it "reads file[:max_rows]" do
      expect(build.max_rows).to eq(100)
    end
  end
end
