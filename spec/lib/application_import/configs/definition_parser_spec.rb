RSpec.describe ApplicationImport::Configs::DefinitionParser do
  let(:columns) { { "email" => { "required" => true }, "name" => nil } }

  let(:invalid_config) do
    {
      "unknown" => 1, "on_error" => "ignore", "handler" => 1,
      "file" => { "formats" => [ "pdf" ], "max_size" => 0, "encoding" => "nope", "csv" => { "sep" => "," }, "extra" => 1 },
      "output" => { "mode" => "database", "batch_size" => "x", "upsert" => { "update" => [ "age" ] } }
    }
  end

  def parse(config)
    described_class.new(:users, { "columns" => columns }.merge(config)).parse
  end

  def config_error(config)
    parse(config)
  rescue ApplicationImport::Errors::ConfigError => e
    e.message.delete_prefix("users: ").split("; ")
  end

  it "applies defaults" do
    result = parse({})

    expect(result.except(:columns)).to eq(
      handler: ApplicationImport::Handler,
      file: { validator: ApplicationImport::FileValidator, formats: [ :csv ], name_pattern: nil, max_size: 10_485_760, max_rows: 100_000,
              encoding: "UTF-8", csv: {}, xlsx: {} },
      validators: [],
      output: { mode: :raw, model: nil, batch_size: 1000, upsert: nil },
      on_error: ApplicationImport::ErrorPolicy.new
    )
    expect(result[:columns].map(&:key)).to eq(%i[ email name ])
  end

  it "returns a deeply frozen result" do
    expect(Ractor.shareable?(parse({ "file" => { "name_pattern" => "x" } }))).to be(true)
  end

  it "does not freeze the caller's config" do
    config = { "columns" => { "joined_on" => { "type" => "date", "date_format" => +"%d/%m/%Y" } } }
    described_class.new(:users, config).parse

    expect([ config.frozen?, config["columns"]["joined_on"]["date_format"].frozen? ]).to eq([ false, false ])
  end

  it "accepts symbol keys" do
    expect(described_class.new(:users, { columns: { email: nil }, on_error: :skip }).parse[:on_error].default).to eq(:skip)
  end

  it "parses file options" do
    file = parse({ "file" => { "formats" => [ "csv", "xlsx", "csv" ], "name_pattern" => '\Ausers\.csv\z', "max_size" => 1,
                               "max_rows" => 2, "encoding" => "shift_jis", "csv" => { "col_sep" => ";" },
                               "xlsx" => { "sheet" => "Data" } } })[:file]

    expect(file.except(:validator)).to eq(formats: %i[ csv xlsx ], name_pattern: /\Ausers\.csv\z/, max_size: 1, max_rows: 2,
      encoding: "Shift_JIS", csv: { col_sep: ";" }, xlsx: { sheet: "Data" })
  end

  it "collects every error into one ConfigError" do
    expect(config_error(invalid_config)).to contain_exactly(
      "config has unknown keys: unknown",
      "handler must be a class name",
      "file has unknown keys: extra",
      "file.formats must be one of csv, xlsx",
      "file.max_size must be an integer >= 1",
      "file.encoding is not a known encoding: nope",
      "file.csv has unknown keys: sep",
      "output.model is required when mode is database",
      "output.batch_size must be an integer >= 1",
      "output.upsert.update references unknown columns: age",
      "output.upsert.conflict_target must be a non-empty list of names",
      "on_error must be one of abort, skip"
    )
  end

  it "rejects a config that is not a mapping" do
    expect { described_class.new(:users, []).parse }
      .to raise_error(ApplicationImport::Errors::ConfigError, /config must be a mapping/)
  end

  it "parses database output with upsert" do
    stub_const("ImportUser", Class.new(ApplicationRecord))
    output = parse({ "output" => { "mode" => "database", "model" => "ImportUser", "batch_size" => 500,
                                   "upsert" => { "conflict_target" => [ "email" ], "update" => [ "name" ] } } })[:output]

    expect(output).to eq(mode: :database, model: ImportUser, batch_size: 500,
      upsert: { conflict_target: [ :email ], update: [ :name ] })
  end

  describe "class references" do
    it "resolves configured classes once" do
      handler = stub_const("UsersHandler", Class.new(ApplicationImport::Handler))
      validator = stub_const("UsersFileValidator", Class.new(ApplicationImport::FileValidator))
      domain = stub_const("DomainValidator", Class.new)
      result = parse({ "handler" => "UsersHandler", "file" => { "validator" => "UsersFileValidator" },
                       "validators" => [ { "class" => "DomainValidator" } ] })

      expect([ result[:handler], result[:file][:validator], result[:validators].first[:class] ])
        .to eq([ handler, validator, domain ])
    end

    it "raises InvalidHandlerError for a handler not inheriting Handler" do
      expect { parse({ "handler" => "String" }) }.to raise_error(ApplicationImport::Errors::InvalidHandlerError)
    end

    it "raises InvalidFileValidatorError for a file validator not inheriting FileValidator" do
      expect { parse({ "file" => { "validator" => "String" } }) }
        .to raise_error(ApplicationImport::Errors::InvalidFileValidatorError)
    end

    it "raises InvalidClassError for a missing validator class" do
      expect { parse({ "validators" => [ { "class" => "MissingValidator" } ] }) }
        .to raise_error(ApplicationImport::Errors::InvalidClassError, "MissingValidator not found")
    end

    it "raises InvalidClassError for a model that is not an ActiveRecord model" do
      expect { parse({ "output" => { "mode" => "database", "model" => "String" } }) }
        .to raise_error(ApplicationImport::Errors::InvalidClassError, "String must inherit from ActiveRecord::Base")
    end
  end

  it "parses configs/config.example.yml" do
    stub_const("User", Class.new(ApplicationRecord))
    stub_const("Imports::UsersHandler", Class.new(ApplicationImport::Handler))
    stub_const("Imports::UsersFileValidator", Class.new(ApplicationImport::FileValidator))
    stub_const("Imports::Users::DomainValidator", Class.new)
    config = YAML.safe_load_file(Rails.root.join("lib/application_import/configs/config.example.yml"))

    result = described_class.new(:example, config).parse

    expect(result[:columns].map(&:type)).to eq(%i[ string string integer decimal boolean string date datetime ])
  end
end
