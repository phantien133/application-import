RSpec.describe ApplicationImport::Configs::DefinitionParser do
  let(:columns) { { "email" => { "required" => true }, "name" => nil } }

  let(:invalid_config) do
    {
      "unknown" => 1, "on_error" => "ignore", "handler" => 1,
      "file" => { "formats" => [ "pdf" ], "max_size" => 0, "encoding" => "nope", "headers" => "yes", "csv" => { "sep" => "," }, "extra" => 1 },
      "output" => { "mode" => "bulk", "batch_size" => "x", "upsert" => { "update" => [ "age" ] } }
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
      file: { checker: ApplicationImport::FileChecker, formats: nil, name_pattern: nil, max_size: nil,
              format: :csv, reader: nil, encoding: "UTF-8", headers: true, require_all_headers: false, unknown_headers: :skip, extra_cells: :warn, assign: nil, numbers: nil, csv: {}, xlsx: {} },
      transformers: [],
      mapper: nil,
      validators: { file: [], row: [], rows: [], verify: [] },
      output: { mode: :raw, model: nil, batch_size: 1000, transaction: true, stream: false, upsert: nil, import: {}, save: {} },
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
                               "format" => "xlsx", "encoding" => "shift_jis", "headers" => false, "require_all_headers" => true, "unknown_headers" => "keep", "extra_cells" => "reject", "csv" => { "col_sep" => ";" },
                               "xlsx" => { "sheet" => "Data" } } })[:file]

    expect(file.except(:checker)).to eq(formats: %i[ csv xlsx ], name_pattern: /\Ausers\.csv\z/, max_size: 1,
      format: :xlsx, reader: nil, encoding: "Shift_JIS", headers: false, require_all_headers: true, unknown_headers: :keep, extra_cells: :reject, assign: nil, numbers: nil, csv: { col_sep: ";" }, xlsx: { sheet: "Data" })
  end

  it "requires file.format to be an allowed format" do
    expect(config_error({ "file" => { "formats" => [ "csv" ], "format" => "xlsx" } }))
      .to eq([ "file.format must be one of file.formats (csv)" ])
  end

  it "rejects a non-boolean file.require_all_headers" do
    expect(config_error({ "file" => { "require_all_headers" => "yes" } })).to eq([ "file.require_all_headers must be true or false" ])
  end

  it "rejects an unknown file.unknown_headers" do
    expect(config_error({ "file" => { "unknown_headers" => "drop" } })).to eq([ "file.unknown_headers must be one of skip, keep, assign, reject" ])
  end

  describe "validator keys" do
    let(:unique) { { "validators" => { "rows" => [ { "type" => "unique_in_file", "keys" => [ "user_email" ] } ] } } }

    it "are checked against the declared columns without transformers or mapper" do
      expect(config_error(unique)).to eq([ "validators.rows[0].keys references unknown columns: user_email" ])
    end

    it "are left to the run with a mapper or transformers" do
      mapper = { "type" => "rename", "attributes" => { "email" => "user_email" } }
      transformers = [ { "type" => "concat", "from" => [ "email" ], "to" => "user_email" } ]

      expect { parse(unique.merge("mapper" => mapper)) }.not_to raise_error
      expect { parse(unique.merge("transformers" => transformers)) }.not_to raise_error
    end
  end

  it "rejects an unknown file.extra_cells" do
    expect(config_error({ "file" => { "extra_cells" => "drop" } })).to eq([ "file.extra_cells must be one of warn, ignore, reject" ])
  end

  it "requires output.model for unknown_headers: assign" do
    expect(config_error({ "file" => { "unknown_headers" => "assign" } })).to eq([ "file.unknown_headers assign needs output.model" ])
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
      "output.model is required when mode is bulk",
      "output.batch_size must be an integer >= 1",
      "output.upsert.conflict_target must be a non-empty list of names",
      "on_error must be one of abort, skip"
    )
  end

  it "rejects a config that is not a mapping" do
    expect { described_class.new(:users, []).parse }
      .to raise_error(ApplicationImport::Errors::ConfigError, /config must be a mapping/)
  end

  it "parses bulk output with upsert and import options" do
    stub_const("ImportUser", Class.new(ApplicationRecord))
    output = parse({ "output" => { "mode" => "bulk", "model" => "ImportUser", "batch_size" => 500, "transaction" => false,
                                   "upsert" => { "conflict_target" => [ "email" ], "update" => [ "name" ] },
                                   "import" => { "validate" => false, "timestamps" => false } } })[:output]

    expect(output).to eq(mode: :bulk, model: ImportUser, batch_size: 500, transaction: false, stream: false,
      upsert: { conflict_target: [ :email ], update: [ :name ] }, import: { validate: false, timestamps: false }, save: {})
  end

  describe "file.assign" do
    before { stub_const("AssignUser", Class.new(ApplicationRecord)) }

    def assign_config(assign, unknown_headers: "assign")
      { "file" => { "unknown_headers" => unknown_headers, **(assign.nil? ? {} : { "assign" => assign }) }, "output" => { "model" => "AssignUser" } }
    end

    it "parses allow or ignore as attribute names" do
      expect([ parse(assign_config({ "allow" => [ "Phone", "note" ] }))[:file][:assign], parse(assign_config({ "ignore" => "admin" }))[:file][:assign] ])
        .to eq([ { allow: %w[ phone note ] }, { ignore: %w[ admin ] } ])
    end

    it "requires exactly one of allow, ignore" do
      expect([ config_error(assign_config({ "allow" => [ "a" ], "ignore" => [ "b" ] })), config_error(assign_config({})) ])
        .to all(eq([ "file.assign needs exactly one of allow, ignore" ]))
    end

    it "rejects unknown keys and empty lists" do
      expect(config_error(assign_config({ "allow" => [], "only" => 1 })))
        .to contain_exactly("file.assign has unknown keys: only", "file.assign.allow must be a non-empty list of names")
    end

    it "is only used with unknown_headers: assign" do
      expect(config_error(assign_config({ "allow" => [ "a" ] }, unknown_headers: "keep")))
        .to eq([ "file.assign is only used with unknown_headers: assign" ])
    end

    it "warns at load when assign has no list" do
      log = StringIO.new
      ApplicationImport.configure { |config| config.logger = ActiveSupport::Logger.new(log) }

      parse(assign_config(nil))

      expect(log.string).to include("users: unknown_headers: assign without file.assign allow / ignore")
    ensure
      ApplicationImport.reset_configuration!
    end

    it "does not warn with a list" do
      log = StringIO.new
      ApplicationImport.configure { |config| config.logger = ActiveSupport::Logger.new(log) }

      parse(assign_config({ "allow" => [ "phone" ] }))

      expect(log.string).to eq("")
    ensure
      ApplicationImport.reset_configuration!
    end
  end

  describe "upsert attributes" do
    before do
      ActiveRecord::Base.connection.create_table(:upsert_spec_users, temporary: true) do |t|
        t.string :email
        t.string :name
      end
      stub_const("UpsertSpecUser", Class.new(ApplicationRecord) { self.table_name = "upsert_spec_users" })
    end

    def upsert(conflict_target, update)
      parse({ "output" => { "model" => "UpsertSpecUser", "upsert" => { "conflict_target" => conflict_target, "update" => update } } })
    end

    it "accepts model attributes, including names produced by transformers or the mapper" do
      expect { upsert([ "email" ], [ "name" ]) }.not_to raise_error
    end

    it "rejects names that are not attributes of the model" do
      expect { upsert([ "mail" ], %w[ name nickname ]) }
        .to raise_error(ApplicationImport::Errors::ConfigError, "users: output.upsert references unknown UpsertSpecUser attributes: mail, nickname")
    end

    it "is skipped when the model's attributes cannot be read (no table yet)" do
      stub_const("NoTableUser", Class.new(ApplicationRecord) { self.table_name = "no_such_table" })

      expect { parse({ "output" => { "model" => "NoTableUser", "upsert" => { "conflict_target" => [ "x" ], "update" => [ "y" ] } } }) }
        .not_to raise_error
      expect(ActiveRecord::Base.connection.select_value("SELECT 1")).to eq(1)
    end
  end

  describe "output options" do
    def output_error(output)
      stub_const("ImportUser", Class.new(ApplicationRecord))
      config_error({ "output" => { "model" => "ImportUser", **output } })
    end

    it "requires upsert.update" do
      expect(output_error("upsert" => { "conflict_target" => [ "email" ] }))
        .to eq([ "output.upsert.update must be a non-empty list of names" ])
    end

    it "rejects import options the bulk writer does not support" do
      expect(output_error("import" => { "track_validation_failures" => true, "raise_error" => true, "validate" => true }))
        .to eq([ "output.import has unsupported options: track_validation_failures, raise_error" ])
    end

    it "rejects on_duplicate_key options together with upsert" do
      expect(output_error("upsert" => { "conflict_target" => [ "email" ], "update" => [ "name" ] },
        "import" => { "on_duplicate_key_ignore" => true }))
        .to eq([ "output.import on_duplicate_key_ignore cannot be combined with upsert" ])
    end

    it "accepts on_duplicate_key_ignore and all_or_none without upsert" do
      expect(output_error("import" => { "on_duplicate_key_ignore" => true, "all_or_none" => true })).to be_a(Hash)
    end

    it "rejects save options other than validate, context and touch" do
      expect(output_error("mode" => "save", "save" => { "validate" => false, "context" => "import", "touch" => false, "nope" => 1 }))
        .to eq([ "output.save has unsupported options: nope" ])
    end
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

    it "resolves column casters" do
      caster = stub_const("PhoneCaster", Class.new(ApplicationImport::Casters::Base))
      columns = described_class.new(:users, { "columns" => { "phone" => { "caster" => "PhoneCaster" }, "name" => nil } }).parse[:columns]

      expect(columns.map { |column| column.options[:caster] }).to eq([ caster, nil ])
    end

    it "raises InvalidCasterError for a caster not inheriting Casters::Base" do
      expect { described_class.new(:users, { "columns" => { "phone" => { "caster" => "String" } } }).parse }
        .to raise_error(ApplicationImport::Errors::InvalidCasterError, "String must inherit from ApplicationImport::Casters::Base")
    end

    it "resolves the model of a model validator, falling back to output.model" do
      model = stub_const("ImportSpecUser", Class.new(ApplicationRecord))
      own = parse({ "validators" => { "row" => [ { "type" => "model", "model" => "ImportSpecUser" } ] } })[:validators][:row].first
      fallback = parse({ "validators" => { "row" => [ { "type" => "model" } ] }, "output" => { "model" => "ImportSpecUser" } })

      expect([ own[:options][:model], fallback[:validators][:row].first[:options][:model], fallback[:output][:model] ])
        .to eq([ model, nil, model ])
    end

    it "requires a model for a model validator without output.model" do
      expect { parse({ "validators" => { "row" => [ { "type" => "model" } ] } }) }
        .to raise_error(ApplicationImport::Errors::ConfigError, "users: validators.row[0].model is required without output.model")
    end

    it "raises InvalidClassError for a model validator model that is not an ActiveRecord model" do
      expect { parse({ "validators" => { "row" => [ { "type" => "model", "model" => "String" } ] } }) }
        .to raise_error(ApplicationImport::Errors::InvalidClassError, "String must inherit from ActiveRecord::Base")
    end

    it "rejects abstract models and ActiveRecord::Base as output.model" do
      expect { parse({ "output" => { "model" => "ApplicationRecord" } }) }
        .to raise_error(ApplicationImport::Errors::InvalidClassError, "users: output.model must be a concrete model, ApplicationRecord is abstract")
      expect { parse({ "output" => { "model" => "ActiveRecord::Base" } }) }
        .to raise_error(ApplicationImport::Errors::InvalidClassError, /must be a concrete model, ActiveRecord::Base is abstract/)
    end

    it "rejects an abstract model for a model validator" do
      expect { parse({ "validators" => { "row" => [ { "type" => "model", "model" => "ApplicationRecord" } ] } }) }
        .to raise_error(ApplicationImport::Errors::InvalidClassError, "users: validators.row[0].model must be a concrete model, ApplicationRecord is abstract")
    end

    it "raises InvalidClassError for a model that is not an ActiveRecord model" do
      expect { parse({ "output" => { "mode" => "bulk", "model" => "String" } }) }
        .to raise_error(ApplicationImport::Errors::InvalidClassError, "String must inherit from ActiveRecord::Base")
    end
  end

  describe "example definitions" do
    def parse_example(name)
      described_class.new(name.to_sym, YAML.safe_load_file(Rails.root.join("lib/application_import/example/#{name}.yml"))).parse
    end

    before do
      models = %w[ User Order Product Member ]
      classes = {
        ApplicationImport::Handler => %w[ Imports::UsersHandler Imports::MembersHandler ],
        ApplicationImport::FileChecker => %w[ Imports::UsersFileChecker Imports::MembersFileChecker ],
        ApplicationImport::Readers::Base => %w[ Imports::FixedWidthReader ],
        ApplicationImport::Casters::Base => %w[ Imports::PhoneCaster Imports::CardNumberCaster ],
        ApplicationImport::Transformers::Base => %w[ Imports::Contacts::PhoneNormalizer ],
        ApplicationImport::Validators::FileValidator => %w[ Imports::Users::FileDateValidator ],
        ApplicationImport::Validators::RowValidator => %w[ Imports::Users::DomainValidator ],
        ApplicationImport::Validators::VerifyValidator => %w[ Imports::Users::ManagersExistValidator Imports::Orders::TotalsValidator ]
      }
      models.each { |name| stub_const(name, Class.new(ApplicationRecord)) }
      classes.each { |base, names| names.each { |name| stub_const(name, Class.new(base)) } }
    end

    it "parses every example file" do
      names = Rails.root.glob("lib/application_import/example/[!_]*.yml").map { |path| File.basename(path, ".yml") }

      expect(names).to match_array(%w[ users orders products contacts members ])
      names.each { |name| expect { parse_example(name) }.not_to raise_error }
    end

    it "parses users.yml, the full reference" do
      result = parse_example(:users)

      expect(result[:columns].map(&:type)).to eq(%i[ string string integer decimal boolean string string date datetime ])
      expect(result[:columns].find { |column| column.key == :phone }.options[:caster]).to eq(Imports::PhoneCaster)
    end

    it "parses the scenario options" do
      orders, products, contacts, members = %w[ orders products contacts members ].map { |name| parse_example(name) }

      expect([ orders[:file][:numbers], orders[:output][:mode], orders[:on_error].max_errors ])
        .to eq([ { decimal_separator: ",", thousands_separator: "." }, :save, 500 ])
      expect([ products[:output][:stream], products[:file][:assign] ]).to eq([ true, { ignore: %w[ admin_note price_cents ] } ])
      expect([ contacts[:file][:headers], contacts[:output][:mode], contacts[:mapper][:options][:only] ]).to eq([ false, :raw, true ])
      expect([ members[:file][:reader], members[:file][:unknown_headers] ]).to eq([ Imports::FixedWidthReader, :reject ])
    end
  end
end
