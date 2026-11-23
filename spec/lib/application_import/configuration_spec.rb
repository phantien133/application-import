RSpec.describe ApplicationImport::Configuration do
  subject(:configuration) { described_class.new }

  let(:dir) { Pathname(Dir.mktmpdir) }

  after do
    FileUtils.remove_entry(dir)
    ApplicationImport.reset_configuration!
  end

  describe "built-in defaults" do
    it "uses config/imports and no definition defaults" do
      expect([ configuration.config_path, configuration.defaults ]).to eq([ Rails.root.join("config/imports"), {} ])
    end

    it "resolves a relative config_path against Rails.root and keeps absolute paths" do
      configuration.config_path = "app/imports"
      expect(configuration.config_path).to eq(Rails.root.join("app/imports"))

      configuration.config_path = dir
      expect(configuration.config_path).to eq(dir)
    end
  end

  describe "#defaults=" do
    it "stringifies and deep-freezes the mapping" do
      configuration.defaults = { file: { max_size: 1 } }

      expect(configuration.defaults).to eq("file" => { "max_size" => 1 })
      expect(configuration.defaults["file"]).to be_frozen
    end

    it "rejects keys that cannot have defaults" do
      expect { configuration.defaults = { columns: {} } }
        .to raise_error(ApplicationImport::Errors::ConfigError, "defaults has unknown keys: columns")
    end

    it "rejects non-mappings" do
      expect { configuration.defaults = [] }.to raise_error(ApplicationImport::Errors::ConfigError, "defaults must be a mapping")
    end
  end

  describe "#load_file" do
    it "applies a flat settings file" do
      dir.join("s.yml").write("config_path: #{dir}\ndefaults:\n  on_error: skip\n")

      configuration.load_file(dir.join("s.yml"))

      expect([ configuration.config_path, configuration.defaults ]).to eq([ dir, { "on_error" => "skip" } ])
    end

    it "merges shared with the current environment section" do
      dir.join("s.yml").write(<<~YAML)
        shared:
          defaults: { file: { max_size: 1, max_rows: 2 } }
        test:
          defaults: { file: { max_rows: 3 } }
        production:
          config_path: /nowhere
      YAML

      configuration.load_file(dir.join("s.yml"))

      expect([ configuration.config_path, configuration.defaults ])
        .to eq([ Rails.root.join("config/imports"), { "file" => { "max_size" => 1, "max_rows" => 3 } } ])
    end

    it "raises on unknown keys, missing files and invalid YAML" do
      dir.join("unknown.yml").write("foo: 1\n")
      dir.join("broken.yml").write("defaults: [\n")

      expect { configuration.load_file(dir.join("unknown.yml")) }.to raise_error(ApplicationImport::Errors::ConfigError, /unknown keys: foo/)
      expect { configuration.load_file(dir.join("none.yml")) }.to raise_error(ApplicationImport::Errors::ConfigError, /settings not found/)
      expect { configuration.load_file(dir.join("broken.yml")) }.to raise_error(ApplicationImport::Errors::ConfigError, /invalid YAML/)
    end
  end

  it "loads example/_config.yml" do
    configuration.load_file("lib/application_import/example/_config.yml")

    expect([ configuration.config_path, configuration.defaults.dig("file", "max_rows") ])
      .to eq([ Rails.root.join("config/imports"), 1000 ])
  end

  describe "#load_settings" do
    it "keeps the built-in defaults when the settings file is absent" do
      allow(Rails.root).to receive(:join).and_call_original
      allow(Rails.root).to receive(:join).with(described_class::SETTINGS_FILE).and_return(dir.join("missing.yml"))

      expect(configuration.load_settings.config_path).to eq(Rails.root.join("config/imports"))
    end

    it "reads the settings file when present" do
      dir.join("_config.yml").write("config_path: #{dir}\n")
      allow(Rails.root).to receive(:join).and_call_original
      allow(Rails.root).to receive(:join).with(described_class::SETTINGS_FILE).and_return(dir.join("_config.yml"))

      expect(configuration.load_settings.config_path).to eq(dir)
    end
  end

  describe "#with_defaults" do
    it "deep-merges defaults under the definition config, definition values winning" do
      configuration.defaults = { file: { max_size: 1, max_rows: 2 }, on_error: "skip" }

      expect(configuration.with_defaults("file" => { "max_rows" => 5 }, "columns" => { "email" => nil }))
        .to eq("file" => { "max_size" => 1, "max_rows" => 5 }, "on_error" => "skip", "columns" => { "email" => nil })
    end

    it "leaves the config untouched without defaults or when it is not a mapping" do
      config = { "file" => {} }

      expect(configuration.with_defaults(config)).to be(config)
      configuration.defaults = { on_error: "skip" }
      expect(configuration.with_defaults([])).to eq([])
    end
  end

  describe "ApplicationImport.configuration" do
    it "is built lazily, memoized, and rebuilt after reset" do
      ApplicationImport.reset_configuration!
      allow(described_class).to receive(:new).and_call_original

      first = ApplicationImport.configuration

      expect(ApplicationImport.configuration).to be(first)
      ApplicationImport.reset_configuration!
      expect(ApplicationImport.configuration).not_to be(first)
      expect(described_class).to have_received(:new).twice
    end

    it "applies configure overrides and drops cached definitions" do
      allow(ApplicationImport).to receive(:clear_definitions!).and_call_original

      ApplicationImport.configure { |config| config.config_path = dir }

      expect(ApplicationImport.configuration.config_path).to eq(dir)
      expect(ApplicationImport).to have_received(:clear_definitions!)
    end
  end
end
