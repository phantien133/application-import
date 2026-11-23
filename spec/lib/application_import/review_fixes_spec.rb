# Regressions for the issues found by the full library review (R6), run end to end
# through ApplicationImport.run unless the fix is local to one class.
RSpec.describe "ApplicationImport review fixes" do # rubocop:disable RSpec/DescribeClass
  let(:log) { StringIO.new }
  let(:logger) { ActiveSupport::Logger.new(log).tap { |l| l.formatter = ->(severity, _, _, msg) { "#{severity} #{msg}\n" } } }
  let(:three) { "Email,Name\na@x.io,Ann\nb@x.io,Bob\nc@x.io,Cy\n" }

  before do
    ActiveRecord::Base.connection.create_table(:review_users, temporary: true) do |t|
      t.string :email
      t.string :name
      t.integer :age
    end
    stub_const("ReviewUser", Class.new(ApplicationRecord) { self.table_name = "review_users" })
  end

  def columns
    { "email" => { "header" => "Email", "required" => true }, "name" => { "header" => "Name" } }
  end

  def definition(**config)
    ApplicationImport::Definition.new(:users, { "columns" => columns, **config.transform_keys(&:to_s) })
  end

  def run(content, **config)
    ApplicationImport.run(definition(**config), StringIO.new(content), filename: "users.csv", logger:)
  end

  def config_error(**config)
    definition(**config)
    nil
  rescue ApplicationImport::Errors::ConfigError => e
    e.message
  end

  def errors_of(result)
    result.errors.map { |error| [ error.line, error.code ] }
  end

  describe "bulk writer" do
    it "keeps rows whose new records share an id (records compare by id)" do
      ActiveRecord::Base.connection.create_table(:review_ids, id: false, temporary: true) do |t|
        t.integer :id, primary_key: true
        t.string :email
      end
      stub_const("ReviewId", Class.new(ApplicationRecord) { self.table_name = "review_ids" })
      result = ApplicationImport.run(
        ApplicationImport::Definition.new(:ids, { "columns" => { "id" => { "type" => "integer" }, "email" => nil },
                                                  "output" => { "model" => "ReviewId" }, "on_error" => "skip" }),
        StringIO.new("id,email\n5,a@x.io\n5,b@x.io\n"), filename: "ids.csv", logger:
      )

      expect([ result.stats.values_at(:written, :invalid), errors_of(result) ]).to eq([ [ 0, 2 ], [ [ 2, :not_saved ], [ 3, :not_saved ] ] ])
    end
  end

  describe "output.stream with a rows error naming a written line" do
    before do
      stub_const("LateConflict", Class.new(ApplicationImport::Handler) do
        define_method(:validate_rows) do |row, _result, _cache|
          raise ApplicationImport::Errors::RowsError.new("conflicts with line 2", lines: [ 2, row.line ]) if row.line == 4
        end
      end)
    end

    it "puts the error on the row being checked; the written row stays written" do
      result = run(three, handler: "LateConflict", output: { "model" => "ReviewUser", "stream" => true, "batch_size" => 1 }, on_error: "skip")

      expect([ errors_of(result), result.errors.first.details[:lines], result.stats.values_at(:valid, :invalid, :written) ])
        .to eq([ [ [ 4, :rows_conflict ] ], [ 2, 4 ], [ 2, 1, 2 ] ])
      expect(ReviewUser.pluck(:email)).to eq(%w[ a@x.io b@x.io ])
    end
  end

  describe "verify" do
    it "hands a row skipped by a verify validator to neither the next one nor handler.verify" do
      seen = []
      stub_const("DropBob", Class.new(ApplicationImport::Validators::VerifyValidator) do
        define_method(:call) { |rows, _result, _cache| rows.find { |row| row.attributes[:name] == "Bob" }.add_error(code: :bob, message: "no") }
      end)
      stub_const("SeeRows", Class.new(ApplicationImport::Validators::VerifyValidator) do
        define_method(:call) { |rows, _result, _cache| seen << rows.map(&:line) }
      end)
      stub_const("SeeHandler", Class.new(ApplicationImport::Handler) do
        define_method(:verify) { |rows, _result, _cache| seen << rows.map(&:line) }
      end)

      run(three, handler: "SeeHandler", validators: { "verify" => [ { "class" => "DropBob" }, { "class" => "SeeRows" } ] }, on_error: "skip")

      expect(seen).to eq([ [ 2, 4 ], [ 2, 4 ] ])
    end
  end

  describe "column rules" do
    it "compares inclusion on decimals by value" do
      result = run("Email,Qty\na@x.io,1\nb@x.io,1.0\nc@x.io,3\n",
        columns: { "email" => nil, "qty" => { "header" => "Qty", "type" => "decimal", "inclusion" => [ 1, 2 ] } }, on_error: "skip")

      expect(errors_of(result)).to eq([ [ 4, :not_included ] ])
    end

    it "matches format on the file text, not the cast value" do
      result = run("Email;Price\na@x.io;1,50\nb@x.io;1,5\n", on_error: "skip",
        columns: { "email" => nil, "price" => { "header" => "Price", "type" => "decimal", "format" => '\A\d+,\d{2}\z' } },
        file: { "csv" => { "col_sep" => ";" }, "numbers" => { "decimal_separator" => "," } })

      expect(errors_of(result)).to eq([ [ 3, :invalid_format ] ])
    end
  end

  describe "map with to + unique_in_file" do
    it "sets `to` to nil for a blank value instead of failing the run" do
      result = run("Email,Role\na@x.io,admin\nb@x.io,\nc@x.io,admin\n", on_error: "skip",
        columns: { "email" => nil, "role" => { "header" => "Role" } },
        transformers: [ { "type" => "map", "attribute" => "role", "values" => { "admin" => "A" }, "to" => "role_code" } ],
        validators: { "rows" => [ { "type" => "unique_in_file", "keys" => [ "role_code" ] } ] })

      expect(errors_of(result)).to eq([ [ 4, :duplicate ] ])
    end
  end

  describe "unique_in_file" do
    it "lets a later row take the key of a row skipped after it was seen" do
      stub_const("SkipFirst", Class.new(ApplicationImport::Handler) do
        define_method(:validate_rows) { |row, _result, _cache| row.add_error(code: :first, message: "no") if row.line == 2 }
      end)

      result = run("Email,Name\na@x.io,Ann\na@x.io,Ann2\n", handler: "SkipFirst", on_error: "skip",
        validators: { "rows" => [ { "type" => "unique_in_file", "keys" => [ "email" ] } ] })

      expect(errors_of(result)).to eq([ [ 2, :first ] ])
    end
  end

  describe "number separators" do
    it "rejects a decimal column whose merged separators clash" do
      expect([
        config_error(columns: { "p" => { "type" => "decimal", "thousands_separator" => "," } }, file: { "numbers" => { "decimal_separator" => "," } }),
        config_error(columns: { "p" => { "type" => "decimal" } }, file: { "numbers" => { "thousands_separator" => "." } })
      ]).to all(include("columns.p thousands_separator"))
    end

    it "allows thousands \".\" for integer columns" do
      expect(config_error(columns: { "p" => { "type" => "integer" } }, file: { "numbers" => { "thousands_separator" => "." } })).to be_nil
    end
  end

  describe "writer errors" do
    it "fails the run on a connection error instead of reporting not_saved rows" do
      allow(ReviewUser).to receive(:import).and_raise(ActiveRecord::ConnectionNotEstablished, "gone")

      expect { run(three, output: { "model" => "ReviewUser" }, on_error: { "default" => "abort", "skip" => [ "not_saved" ] }) }
        .to raise_error(ActiveRecord::ConnectionNotEstablished)
    end

    it "turns an integer out of the column range into not_saved on that row only" do
      columns = { "email" => nil, "age" => { "type" => "integer" } }

      %w[ save bulk ].each do |mode|
        ReviewUser.delete_all
        result = run("email,age\na@x.io,1\nb@x.io,99999999999\n", columns:, output: { "model" => "ReviewUser", "mode" => mode }, on_error: "skip")

        expect([ mode, errors_of(result), ReviewUser.pluck(:email) ]).to eq([ mode, [ [ 3, :not_saved ] ], %w[ a@x.io ] ])
      end
    end

    it "settles row errors raised by handler.write with on_error" do
      stub_const("BadWrite", Class.new(ApplicationImport::Handler) do
        define_method(:write) { |_rows, _writer| raise ApplicationImport::Errors::RowError.new("bad", line: 3, code: :bad_write) }
      end)

      result = run(three, handler: "BadWrite", output: { "model" => "ReviewUser" }, on_error: "skip")

      expect([ result.status, errors_of(result) ]).to eq([ :completed_with_errors, [ [ 3, :bad_write ] ] ])
    end
  end

  describe "defaults" do
    after { ApplicationImport.reset_configuration! }

    it "keeps the defaults of a section left empty in the definition" do
      ApplicationImport.configure { |config| config.defaults = { file: { max_size: 5 } } }

      expect(ApplicationImport::Definition.build(:users, { "columns" => columns, "file" => nil }).file[:max_size]).to eq(5)
    end

    it "requires config_path to be a path" do
      expect { ApplicationImport::Configuration.new.config_path = nil }.to raise_error(ApplicationImport::Errors::ConfigError, /config_path/)
    end
  end

  describe "file reading" do
    it "stops at a record wider than file.max_columns" do
      result = run("Email,Name\na@x.io,Ann,1,2,3\n", file: { "max_columns" => 4 })

      expect([ result.status, errors_of(result), result.errors.first.details ])
        .to eq([ :failed, [ [ nil, :too_many_cells ] ], { line: 2, cells: 5, max_columns: 4 } ])
    end

    it "limits records to columns * 2 + 100 cells by default" do
      result = run("Email,Name\na@x.io,#{(1..104).to_a.join(",")}\n", file: { "extra_cells" => "ignore" })

      expect(result.errors.map(&:code)).to eq(%i[ too_many_cells ])
    end

    it "strips Unicode spaces around headers" do
      result = run("\u00A0Email\u200B,Name\u3000\na@x.io,Ann\n")

      expect([ result.status, result.records ]).to eq([ :completed, [ { email: "a@x.io", name: "Ann" } ] ])
    end

    it "detects a BOM from an IO returning 1 byte per read" do
      short = Class.new(StringIO) do
        def read(length = nil, *)
          super(length && 1)
        end
      end
      io = short.new("\xFF\xFE".b + "Email,Name\na@x.io,Ann\n".encode("UTF-16LE").b)

      result = ApplicationImport.run(definition, ApplicationImport::Source.new(filename: "u.csv", io:), logger:)

      expect(result.records).to eq([ { email: "a@x.io", name: "Ann" } ])
    end

    it "rejects IO it cannot read twice" do
      reader, writer = IO.pipe

      expect { ApplicationImport::Source.build(reader, filename: "u.csv") }.to raise_error(ArgumentError, /seekable/)
    ensure
      [ reader, writer ].each(&:close)
    end

    it "uses the first of file.formats as the default format" do
      expect(definition(file: { "formats" => [ "xlsx" ] }).file[:format]).to eq(:xlsx)
    end
  end

  describe "config checks" do
    it "rejects non-finite bounds and non-String regexps" do
      expect([
        config_error(columns: { "p" => { "type" => "decimal", "min" => Float::NAN } }),
        config_error(columns: { "p" => { "format" => 5 } })
      ]).to eq([ "users: columns.p.min must be a finite number", "users: columns.p.format must be a regexp string" ])
    end

    it "rejects a rename that would overwrite a column" do
      expect(config_error(mapper: { "type" => "rename", "attributes" => { "email" => "name" } }))
        .to eq("users: mapper.attributes would overwrite the columns name (rename them too, or use only: true)")
    end

    it "rejects Rails' own models as output.model" do
      stub_const("ActiveRecord::ReviewInternal", Class.new(ApplicationRecord) { self.table_name = "review_users" })

      expect { definition(output: { "model" => "ActiveRecord::ReviewInternal" }) }
        .to raise_error(ApplicationImport::Errors::InvalidClassError, /must be an application model/)
    end

    it "warns about output options that have no effect in the mode" do
      allow(ApplicationImport.logger).to receive(:warn)

      definition(output: { "batch_size" => 10 })

      expect(ApplicationImport.logger).to have_received(:warn).with(/output.batch_size has no effect when mode is raw/)
    end
  end

  describe "default transformer" do
    it "gives each row its own copy of the value" do
      transformer = ApplicationImport::Transformers::Default.new(definition, { attribute: :tags, value: [].freeze }, context: {}, logger:)

      first, second = 2.times.map { transformer.call({}, nil)[:tags] }

      expect([ first.frozen?, first.equal?(second) ]).to eq([ false, false ])
    end
  end
end
