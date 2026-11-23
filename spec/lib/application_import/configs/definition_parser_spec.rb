RSpec.describe ApplicationImport::Configs::DefinitionParser do
  let(:columns) { { "email" => { "required" => true }, "name" => nil } }

  let(:invalid_config) do
    {
      "unknown" => 1, "on_error" => "ignore", "handler" => 1,
      "file" => { "formats" => [ "pdf" ], "max_size" => 0, "encoding" => "nope", "headers" => "yes", "csv" => { "sep" => "," }, "extra" => 1 },
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
      file: { checker: ApplicationImport::FileChecker, formats: nil, name_pattern: nil, max_size: nil, max_rows: 100_000,
              format: :csv, reader: nil, encoding: "UTF-8", headers: true, unknown_headers: :skip, csv: {}, xlsx: {} },
      validators: { file: [], row: [], rows: [], verify: [] },
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
                               "max_rows" => 2, "format" => "xlsx", "encoding" => "shift_jis", "headers" => false, "unknown_headers" => "keep", "csv" => { "col_sep" => ";" },
                               "xlsx" => { "sheet" => "Data" } } })[:file]

    expect(file.except(:checker)).to eq(formats: %i[ csv xlsx ], name_pattern: /\Ausers\.csv\z/, max_size: 1, max_rows: 2,
      format: :xlsx, reader: nil, encoding: "Shift_JIS", headers: false, unknown_headers: :keep, csv: { col_sep: ";" }, xlsx: { sheet: "Data" })
  end

  it "requires file.format to be an allowed format" do
    expect(config_error({ "file" => { "formats" => [ "csv" ], "format" => "xlsx" } }))
      .to eq([ "file.format must be one of file.formats (csv)" ])
  end

  it "rejects an unknown file.unknown_headers" do
    expect(config_error({ "file" => { "unknown_headers" => "reject" } })).to eq([ "file.unknown_headers must be one of skip, keep" ])
  end

  it "rejects an unknown file.format" do
    expect(config_error({ "file" => { "format" => "pdf" } })).to eq([ "file.format must be one of csv, xlsx" ])
  end

  it "collects every error into one ConfigError" do
    expect(config_error(invalid_config)).to contain_exactly(
      "config has unknown keys: unknown",
      "handler must be a class name",
      "file has unknown keys: extra",
      "file.formats must be one of csv, xlsx",
      "file.max_size must be an integer >= 1",
      "file.encoding is not a known encoding: nope",
      "file.headers must be true or false",
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
      validator = stub_const("UsersFileChecker", Class.new(ApplicationImport::FileChecker))
      domain = stub_const("DomainValidator", Class.new(ApplicationImport::Validators::RowValidator))
      result = parse({ "handler" => "UsersHandler", "file" => { "checker" => "UsersFileChecker" },
                       "validators" => { "row" => [ { "class" => "DomainValidator" } ] } })

      expect([ result[:handler], result[:file][:checker], result[:validators][:row].first[:class] ])
        .to eq([ handler, validator, domain ])
    end

    it "raises InvalidHandlerError for a handler not inheriting Handler" do
      expect { parse({ "handler" => "String" }) }.to raise_error(ApplicationImport::Errors::InvalidHandlerError)
    end

    it "raises InvalidFileCheckerError for a file checker not inheriting FileChecker" do
      expect { parse({ "file" => { "checker" => "String" } }) }
        .to raise_error(ApplicationImport::Errors::InvalidFileCheckerError)
    end

    it "resolves a custom reader" do
      reader = stub_const("UsersReader", Class.new(ApplicationImport::Readers::Base))

      expect(parse({ "file" => { "reader" => "UsersReader" } })[:file][:reader]).to eq(reader)
    end

    it "raises InvalidReaderError for a reader not inheriting Readers::Base" do
      expect { parse({ "file" => { "reader" => "String" } }) }
        .to raise_error(ApplicationImport::Errors::InvalidReaderError, "String must inherit from ApplicationImport::Readers::Base")
    end

    it "raises InvalidClassError for a missing validator class" do
      expect { parse({ "validators" => { "verify" => [ { "class" => "MissingValidator" } ] } }) }
        .to raise_error(ApplicationImport::Errors::InvalidValidatorError, "MissingValidator not found")
    end

    it "raises InvalidValidatorError for a validator in the wrong stage" do
      stub_const("RowCheck", Class.new(ApplicationImport::Validators::RowValidator))

      expect { parse({ "validators" => { "rows" => [ { "class" => "RowCheck" } ] } }) }
        .to raise_error(ApplicationImport::Errors::InvalidValidatorError,
          "RowCheck must inherit from ApplicationImport::Validators::RowsValidator")
    end

    it "resolves built-in validator types to their classes" do
      result = parse({ "validators" => { "rows" => [ { "type" => "unique_in_file", "keys" => [ "email" ] } ] } })

      expect(result[:validators][:rows]).to eq([
        { type: :unique_in_file, class: ApplicationImport::Validators::UniqueInFile, options: { keys: [ :email ] } }
      ])
    end

    it "raises InvalidClassError for a model that is not an ActiveRecord model" do
      expect { parse({ "output" => { "mode" => "database", "model" => "String" } }) }
        .to raise_error(ApplicationImport::Errors::InvalidClassError, "String must inherit from ActiveRecord::Base")
    end
  end

  it "parses example/users.yml" do
    stub_const("User", Class.new(ApplicationRecord))
    stub_const("Imports::UsersHandler", Class.new(ApplicationImport::Handler))
    stub_const("Imports::UsersFileChecker", Class.new(ApplicationImport::FileChecker))
    stub_const("Imports::Users::DomainValidator", Class.new(ApplicationImport::Validators::RowValidator))
    stub_const("Imports::Users::FileDateValidator", Class.new(ApplicationImport::Validators::FileValidator))
    stub_const("Imports::Users::ManagersExistValidator", Class.new(ApplicationImport::Validators::VerifyValidator))
    config = YAML.safe_load_file(Rails.root.join("lib/application_import/example/users.yml"))

    result = described_class.new(:example, config).parse

    expect(result[:columns].map(&:type)).to eq(%i[ string string integer decimal boolean string date datetime ])
  end
end
