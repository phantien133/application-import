RSpec.describe ApplicationImport::Definition do
  let(:parsed) do
    {
      handler: ApplicationImport::Handler, file: { checker: ApplicationImport::FileChecker, format: :csv },
      columns: [], validators: { file: [] }, output: { mode: :raw }, on_error: ApplicationImport::ErrorPolicy.new
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
      [ nil, 1, "", "_config", "Users", "../users", "/etc/passwd", "users.yml", "a b" ].each do |name|
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

    before { ApplicationImport.configure { |config| config.config_path = dir } }

    after do
      ApplicationImport.reset_configuration!
      FileUtils.remove_entry(dir)
    end

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

    it "loads an explicit file path, named after its basename" do
      dir.join("sub").mkpath
      dir.join("sub/members.yaml").write("on_error: skip\n")

      [ dir.join("sub/members.yaml"), dir.join("sub/members.yaml").to_s ].each do |path|
        expect(described_class.load(path).name).to eq(:members)
      end
    end

    it "resolves relative file paths against Rails.root" do
      expect(described_class.locate("app/imports/users.yml")).to eq([ :users, Rails.root.join("app/imports/users.yml") ])
    end

    it "rejects a file path whose basename is not a valid name" do
      expect { described_class.locate(dir.join("Bad-Name.yml")) }
        .to raise_error(ApplicationImport::Errors::ConfigError, /invalid import name: "Bad-Name"/)
    end

    it "applies the configured defaults under the file config" do
      parser_input = nil
      stub_const("ApplicationImport::Configs::DefinitionParser", Class.new do
        define_method(:initialize) { |_name, config| parser_input = config }
        define_method(:parse) { { file: {} } }
      end)
      ApplicationImport.configure { |config| config.defaults = { on_error: "abort", file: { max_size: 5 } } }
      dir.join("users.yml").write("on_error: skip\n")

      described_class.load(:users)

      expect(parser_input).to eq("on_error" => "skip", "file" => { "max_size" => 5 })
    end

    it "raises ConfigError on YAML that is not safe to load" do
      dir.join("unsafe.yml").write("--- !ruby/object:Object {}\n")

      expect { described_class.load(:unsafe) }.to raise_error(ApplicationImport::Errors::ConfigError, /invalid YAML/)
    end
  end

  describe "class readers" do
    it "returns the classes resolved by the parser" do
      handler = stub_const("UsersHandler", Class.new(ApplicationImport::Handler))
      validator = stub_const("UsersFileChecker", Class.new(ApplicationImport::FileChecker))
      definition = build(handler:, file: { checker: validator, format: :csv })

      expect([ definition.handler_class, definition.file_checker_class ]).to eq([ handler, validator ])
    end
  end

  describe "#reader_class" do
    it "is file[:reader] when set" do
      reader = stub_const("UsersReader", Class.new(ApplicationImport::Readers::Base))

      expect(build(file: { reader:, format: :csv }).reader_class).to eq(reader)
    end

    it "falls back to the built-in reader for file[:format], csv by default" do
      expect([ build(file: { format: :xlsx }).reader_class, build(file: {}).reader_class ])
        .to eq([ ApplicationImport::Readers::Xlsx, ApplicationImport::Readers::Csv ])
    end
  end
end
