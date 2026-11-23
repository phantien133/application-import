# End-to-end behaviour of every definition option implemented so far, run through
# ApplicationImport.run: option absent, each accepted value, and invalid values.
# Parsing details live in spec/lib/application_import/configs/*_parser_spec.rb.
RSpec.describe "ApplicationImport config options" do # rubocop:disable RSpec/DescribeClass
  let(:log) { StringIO.new }
  let(:logger) { ActiveSupport::Logger.new(log).tap { |l| l.formatter = ->(severity, _, _, msg) { "#{severity} #{msg}\n" } } }

  before do
    stub_const("ConfigSpecRunner", Class.new(ApplicationImport::Runner) do
      def write_rows
        result.add_records(rows.map(&:attributes))
      end
    end)
  end

  def default_columns
    { "email" => { "header" => "Email", "required" => true }, "name" => { "header" => "Name" } }
  end

  def definition(file: {}, columns: default_columns, **config)
    ApplicationImport::Definition.new(:users, { "file" => file, "columns" => columns, **config.transform_keys(&:to_s) })
  end

  def run(content = "Email,Name\na@x.io,Ann\n", filename: "users.csv", **config)
    ApplicationImport.run(definition(**config), StringIO.new(content.b), filename:, runner: "ConfigSpecRunner", logger:)
  end

  # [status, error codes, records]
  def outcome(content = "Email,Name\na@x.io,Ann\n", filename: "users.csv", **config)
    result = run(content, filename:, **config)
    [ result.status, result.errors.map(&:code), result.records ]
  end

  def config_error(**config)
    definition(**config)
    nil
  rescue ApplicationImport::Errors::ConfigError => e
    e.message
  end

  def ok(*records)
    [ :completed, [], records ]
  end

  def failed(*codes)
    [ :failed, codes, [] ]
  end

  def ann
    { email: "a@x.io", name: "Ann" }
  end

  describe "handler" do
    it "defaults to ApplicationImport::Handler" do
      expect(definition.handler_class).to eq(ApplicationImport::Handler)
    end

    it "uses a custom Handler subclass" do
      calls = []
      stub_const("SpecHandler", Class.new(ApplicationImport::Handler) { define_method(:after_import) { |result| calls << result.status } })

      run(handler: "SpecHandler")

      expect(calls).to eq([ :completed ])
    end

    it "rejects a class that is not a Handler, or a missing one" do
      expect([ config_error(handler: "String"), config_error(handler: "MissingHandler") ])
        .to eq([ "String must inherit from ApplicationImport::Handler", "MissingHandler not found" ])
    end
  end

  describe "file.checker" do
    it "defaults to FileChecker, which warns about each unconfigured check" do
      expect(outcome).to eq(ok(ann))
      expect(log.string.scan(/file\.(\w+) is not configured/).flatten).to eq(%w[ formats name_pattern max_size ])
    end

    it "uses a custom FileChecker subclass" do
      stub_const("SpecChecker", Class.new(ApplicationImport::FileChecker) do
        define_method(:call) { |_source, result| result.add_file_error(:custom, "no") }
      end)

      expect(outcome(file: { "checker" => "SpecChecker" })).to eq(failed(:custom))
    end

    it "rejects a class that is not a FileChecker" do
      expect(config_error(file: { "checker" => "String" })).to eq("String must inherit from ApplicationImport::FileChecker")
    end
  end

  describe "file.formats" do
    it "accepts any extension when absent" do
      expect(outcome(filename: "users.txt")).to eq(ok(ann))
    end

    it "accepts listed extensions case-insensitively and rejects others" do
      file = { "formats" => [ "csv" ] }

      expect([ outcome(filename: "users.CSV", file:), outcome(filename: "users.txt", file:), outcome(filename: "users", file:) ])
        .to eq([ ok(ann), failed(:invalid_format), failed(:invalid_format) ])
    end

    it "accepts a single name" do
      expect(outcome(file: { "formats" => "csv" })).to eq(ok(ann))
    end

    it "lets an allowed extension through while file.format picks the reader" do
      expect(outcome(filename: "users.xlsx", file: { "formats" => %w[ csv xlsx ] })).to eq(ok(ann))
    end

    it "rejects unknown formats and empty lists" do
      expect([ config_error(file: { "formats" => [ "pdf" ] }), config_error(file: { "formats" => [] }) ])
        .to eq([ "users: file.formats must be one of csv, xlsx", "users: file.formats must be a non-empty list of names" ])
    end
  end

  describe "file.name_pattern" do
    it "accepts any filename when absent" do
      expect(outcome(filename: "anything.csv")).to eq(ok(ann))
    end

    it "accepts matching filenames and rejects others" do
      file = { "name_pattern" => '\Ausers_\d{8}\.csv\z' }

      expect([ outcome(filename: "users_20260101.csv", file:), outcome(filename: "users.csv", file:) ])
        .to eq([ ok(ann), failed(:invalid_name) ])
    end

    it "rejects an invalid regexp" do
      expect(config_error(file: { "name_pattern" => "(" })).to start_with("users: file.name_pattern is not a valid regexp")
    end
  end

  describe "file.max_size" do
    let(:content) { "Email,Name\na@x.io,Ann\n" }

    it "accepts any size when absent" do
      expect(outcome(content * 1)).to eq(ok(ann))
    end

    it "accepts sizes up to max_size and rejects bigger files" do
      size = content.bytesize

      expect([ outcome(file: { "max_size" => size }), outcome(file: { "max_size" => size - 1 }) ])
        .to eq([ ok(ann), failed(:too_large) ])
    end

    it "rejects values that are not integers >= 1" do
      expect([ config_error(file: { "max_size" => 0 }), config_error(file: { "max_size" => "1MB" }) ])
        .to all(eq("users: file.max_size must be an integer >= 1"))
    end
  end

  describe "file.format" do
    it "defaults to the CSV reader" do
      expect(definition.reader_class).to eq(ApplicationImport::Readers::Csv)
    end

    it "uses the CSV reader for csv" do
      expect(outcome(file: { "format" => "csv" })).to eq(ok(ann))
    end

    it "uses the XLSX reader for xlsx, not implemented yet" do
      expect { run(file: { "format" => "xlsx" }) }.to raise_error(NotImplementedError, /XLSX reading is not implemented yet/)
    end

    it "rejects unknown formats and formats outside file.formats" do
      expect([ config_error(file: { "format" => "pdf" }), config_error(file: { "format" => "xlsx", "formats" => [ "csv" ] }) ])
        .to eq([ "users: file.format must be one of csv, xlsx", "users: file.format must be one of file.formats (csv)" ])
    end
  end

  describe "file.reader" do
    it "defaults to the reader for file.format" do
      expect(definition(file: { "format" => "xlsx" }).reader_class).to eq(ApplicationImport::Readers::Xlsx)
    end

    it "uses a custom reader over file.format" do
      stub_const("UpcaseReader", Class.new(ApplicationImport::Readers::Csv) do
        private

        def each_record
          super { |line, values| yield line, values.map(&:upcase) }
        end
      end)

      expect(outcome(file: { "reader" => "UpcaseReader", "format" => "xlsx" })).to eq(ok(email: "A@X.IO", name: "ANN"))
    end

    it "rejects a class that is not a reader" do
      expect(config_error(file: { "reader" => "String" })).to eq("String must inherit from ApplicationImport::Readers::Base")
    end
  end

  describe "file.encoding" do
    let(:sjis) { "Email,Name\na@x.io,名前\n".encode("Shift_JIS") }

    it "defaults to UTF-8" do
      expect([ outcome("Email,Name\na@x.io,Tên\n"), outcome(sjis) ])
        .to eq([ ok(email: "a@x.io", name: "Tên"), failed(:invalid_encoding) ])
    end

    it "transcodes a configured encoding, aliases included" do
      expect([ outcome(sjis, file: { "encoding" => "shift_jis" }), outcome("Email,Name\na,caf\xE9\n", file: { "encoding" => "CP1252" }) ])
        .to eq([ ok(email: "a@x.io", name: "名前"), ok(email: "a", name: "café") ])
    end

    it "lets a BOM win over the configured encoding" do
      content = "\xFF\xFE".b + "Email,Name\na@x.io,Ann\n".encode("UTF-16LE").b

      expect(outcome(content, file: { "encoding" => "Shift_JIS" })).to eq(ok(ann))
    end

    it "rejects unknown encodings" do
      expect(config_error(file: { "encoding" => "nope" })).to eq("users: file.encoding is not a known encoding: nope")
    end

    it "rejects encodings Ruby cannot convert to UTF-8, and host-dependent aliases" do
      expect([ config_error(file: { "encoding" => "Windows-1258" }), config_error(file: { "encoding" => "EUC-TW" }),
        config_error(file: { "encoding" => "locale" }) ])
        .to eq([ "users: file.encoding cannot be converted to UTF-8: Windows-1258", "users: file.encoding cannot be converted to UTF-8: EUC-TW",
          "users: file.encoding must name an encoding, not locale" ])
    end

    it "reads convertible dummy encodings" do
      content = "Email,Name\na@x.io,名前\n".encode("ISO-2022-JP")

      expect(outcome(content, file: { "encoding" => "ISO-2022-JP" })).to eq(ok(email: "a@x.io", name: "名前"))
    end

    it "accepts UTF-16 / UTF-32 (a BOM is then required in the file)" do
      expect([ config_error(file: { "encoding" => "UTF-16" }), outcome("Email,Name\na,b\n", file: { "encoding" => "UTF-16" }) ])
        .to eq([ nil, failed(:invalid_encoding) ])
    end
  end

  describe "file.headers" do
    it "reads a header row by default and with true" do
      expect([ outcome, outcome(file: { "headers" => true }) ]).to all(eq(ok(ann)))
    end

    it "maps cells by column position with false" do
      expect(outcome("a@x.io,Ann\nb@x.io,Bob\n", file: { "headers" => false }))
        .to eq(ok(ann, { email: "b@x.io", name: "Bob" }))
    end

    it "rejects non-booleans" do
      expect(config_error(file: { "headers" => "yes" })).to eq("users: file.headers must be true or false")
    end
  end

  describe "file.require_all_headers" do
    it "only requires required columns by default and with false" do
      expected = ok(email: "a@x.io", name: nil)

      expect([ outcome("Email\na@x.io\n"), outcome("Email\na@x.io\n", file: { "require_all_headers" => false }) ]).to all(eq(expected))
      expect(outcome("Name\nAnn\n")).to eq(failed(:missing_headers))
    end

    it "requires every column with true" do
      expect([ outcome("Email\na@x.io\n", file: { "require_all_headers" => true }), outcome(file: { "require_all_headers" => true }) ])
        .to eq([ failed(:missing_headers), ok(ann) ])
    end

    it "rejects non-booleans" do
      expect(config_error(file: { "require_all_headers" => 1 })).to eq("users: file.require_all_headers must be true or false")
    end
  end

  describe "file.unknown_headers" do
    let(:content) { "Email,Phone,Name\na@x.io,123,Ann\n" }

    it "skips unknown headers by default and with skip" do
      expect([ outcome(content), outcome(content, file: { "unknown_headers" => "skip" }) ]).to all(eq(ok(ann)))
    end

    it "keeps them as attributes with keep" do
      expect(outcome(content, file: { "unknown_headers" => "keep" })).to eq(ok(ann.merge("Phone" => "123")))
    end

    it "rejects them with reject" do
      expect(outcome(content, file: { "unknown_headers" => "reject" })).to eq(failed(:unknown_headers))
    end

    it "keeps extra cells by position without header row" do
      expect(outcome("a@x.io,Ann,123\n", file: { "headers" => false, "unknown_headers" => "keep" }))
        .to eq(ok(ann.merge("column_3" => "123")))
    end

    it "matches headers exactly with require_all_headers + reject" do
      file = { "require_all_headers" => true, "unknown_headers" => "reject" }

      expect([ outcome("Name,Email\nAnn,a@x.io\n", file:), outcome(content, file:), outcome("Email\na\n", file:) ])
        .to eq([ ok(ann), failed(:unknown_headers), failed(:missing_headers) ])
    end

    it "rejects other values" do
      expect(config_error(file: { "unknown_headers" => "drop" })).to eq("users: file.unknown_headers must be one of skip, keep, assign, reject")
    end
  end

  describe "file.extra_cells" do
    let(:content) { "Email,Name\na@x.io,Ann,extra\nb@x.io,Bob\nc@x.io,Cy,x,y\n" }

    def rows_of(file)
      captured = []
      stub_const("RawRunner", Class.new(ApplicationImport::Runner) { define_method(:write_rows) { captured.concat(rows) } })
      result = ApplicationImport.run(definition(file:), StringIO.new(content), filename: "users.csv", runner: "RawRunner", logger:)
      [ result, captured ]
    end

    it "warns by default and with warn, keeping the extra cells in raw only" do
      [ {}, { "extra_cells" => "warn" } ].each do |file|
        result, rows = rows_of(file)

        expect([ result.status, rows.map(&:raw), rows.map(&:attributes) ]).to eq([
          :completed, [ %w[ a@x.io Ann extra ], %w[ b@x.io Bob ], %w[ c@x.io Cy x y ] ],
          [ ann, { email: "b@x.io", name: "Bob" }, { email: "c@x.io", name: "Cy" } ]
        ])
      end
      expect(log.string.scan("line 2 has 1 cells more than the headers").size).to eq(2)
      expect(log.string).to include("2 rows have cells more than the headers")
    end

    it "says nothing with ignore" do
      result, = rows_of("extra_cells" => "ignore")

      expect(result.status).to eq(:completed)
      expect(log.string).not_to include("cells more than the headers")
    end

    it "halts with a file error at the first such row with reject, like a file checker error" do
      result, rows = rows_of("extra_cells" => "reject", "unknown_headers" => "skip")

      expect([ result.status, result.errors.map { |e| [ e.code, e.line, e.message, e.details ] }, rows ]).to eq([
        :failed, [ [ :extra_cells, nil, "line 2 has 1 cells more than the headers", { line: 2, cells: { 3 => "extra" } } ] ], []
      ])
    end

    it "counts cells under a blank header as extra cells" do
      file = { "require_all_headers" => true, "unknown_headers" => "reject", "extra_cells" => "reject" }

      expect(outcome("Email,Name,\na@x.io,Ann,SECRET\n", file:)).to eq(failed(:extra_cells))
      expect(outcome("Email,Name,\na@x.io,Ann,\n", file:)).to eq(ok(ann))
    end

    it "ignores trailing blank cells" do
      expect(outcome("Email,Name\na@x.io,Ann,,\n", file: { "extra_cells" => "reject" })).to eq(ok(ann))
    end

    it "does not apply when unknown cells are kept without header row" do
      expect(outcome("a@x.io,Ann,x\n", file: { "headers" => false, "unknown_headers" => "keep", "extra_cells" => "reject" }))
        .to eq(ok(ann.merge("column_3" => "x")))
    end

    it "rejects other values" do
      expect(config_error(file: { "extra_cells" => "drop" })).to eq("users: file.extra_cells must be one of warn, ignore, reject")
    end
  end

  describe "file.unknown_headers: assign" do
    before do
      ActiveRecord::Base.connection.create_table(:assign_spec_users, temporary: true) do |t|
        t.string :email
        t.string :phone
        t.integer :score
      end
      stub_const("AssignSpecUser", Class.new(ApplicationRecord) do
        self.table_name = "assign_spec_users"
        validates :phone, presence: true
      end)
    end

    def records(content, **config)
      captured = []
      stub_const("RecordRunner", Class.new(ApplicationImport::Runner) { define_method(:write_rows) { captured.concat(rows.map(&:record)) } })
      definition = definition(file: { "unknown_headers" => "assign" }, output: { "model" => "AssignSpecUser" }, **config)
      result = ApplicationImport.run(definition, StringIO.new(content), filename: "users.csv", runner: "RecordRunner", logger:)
      [ result, captured ]
    end

    it "assigns unknown headers naming a model attribute straight to the record, without cast or rules" do
      result, records = records("Email,Name,Phone,Score,Note\na@x.io,Ann, 090 ,7,hi\n")

      expect(result.status).to eq(:completed)
      expect(records.map { |r| [ r.email, r.phone, r.score ] }).to eq([ [ "a@x.io", " 090 ", 7 ] ])
      expect(log.string).to include("not matching a AssignSpecUser attribute, kept but not assigned: Note")
    end

    it "lets the model validations see the assigned values" do
      result, = records("Email,Name,Phone\na@x.io,Ann,\n", validators: { "row" => [ { "type" => "model" } ] }, on_error: "skip")

      expect(result.errors.map { |e| [ e.code, e.column ] }).to eq([ [ :blank, "phone" ] ])
    end

    it "never assigns with keep" do
      _, records = records("Email,Name,Phone\na@x.io,Ann,090\n", file: { "unknown_headers" => "keep" })

      expect(records.first.phone).to be_nil
    end

    it "needs output.model" do
      expect(config_error(file: { "unknown_headers" => "assign" })).to eq("users: file.unknown_headers assign needs output.model")
    end
  end

  describe "file.csv" do
    it "uses commas, double quotes and any line ending by default" do
      expect(outcome("Email,Name\r\na@x.io,\"Ann\"\rb@x.io,Bob\n")).to eq(ok(ann, { email: "b@x.io", name: "Bob" }))
    end

    it "applies col_sep, quote_char and row_sep" do
      csv = { "col_sep" => ";", "quote_char" => "'", "row_sep" => "|" }

      expect(outcome("Email;Name|a@x.io;'A;nn'|", file: { "csv" => csv })).to eq(ok(email: "a@x.io", name: "A;nn"))
    end

    it "keeps a configured row_sep instead of normalizing line endings" do
      expect(outcome("Email,Name\r\na@x.io,\"A\nnn\"\r\n", file: { "csv" => { "row_sep" => "\r\n" } }))
        .to eq(ok(email: "a@x.io", name: "A\nnn"))
    end

    it "is strict about stray quotes unless liberal_parsing is true" do
      content = "Email,Name\na@x.io,say \"hi\"\n"

      expect([ outcome(content), outcome(content, file: { "csv" => { "liberal_parsing" => false } }),
        outcome(content, file: { "csv" => { "liberal_parsing" => true } }) ])
        .to eq([ failed(:malformed_csv), failed(:malformed_csv), ok(email: "a@x.io", name: "say \"hi\"") ])
    end

    it "keeps spaces by default and strips them with strip true or one given character" do
      content = "Email,Name\na@x.io, *Ann* \n"

      expect([ outcome(content), outcome(content, file: { "csv" => { "strip" => false } }),
        outcome(content, file: { "csv" => { "strip" => true } }), outcome("Email,Name\na@x.io,*Ann*\n", file: { "csv" => { "strip" => "*" } }) ]
        .map { |result| result.last.first[:name] }).to eq([ " *Ann* ", " *Ann* ", "*Ann*", "Ann" ])
    end

    it "rejects strip strings of several characters" do
      expect(config_error(file: { "csv" => { "strip" => " *" } })).to eq("users: file.csv.strip must be true, false or a single character")
    end

    it "skips lines matching skip_lines" do
      expect(outcome("# export\nEmail,Name\n# note\na@x.io,Ann\n", file: { "csv" => { "skip_lines" => '\A#' } })).to eq(ok(ann))
    end

    it "rejects fields longer than max_field_size" do
      expect([ outcome(file: { "csv" => { "max_field_size" => 6 } }), outcome(file: { "csv" => { "max_field_size" => 5 } }) ])
        .to eq([ ok(ann), failed(:malformed_csv) ])
    end

    it "hands passthrough options to CSV.new unvalidated" do
      expect(outcome("Email,Name\na@x.io,\n", file: { "csv" => { "passthrough" => { "nil_value" => "-" } } }))
        .to eq(ok(email: "a@x.io", name: "-"))
    end

    it "rejects invalid values and unknown keys" do
      expect([ config_error(file: { "csv" => { "col_sep" => "" } }), config_error(file: { "csv" => { "encoding" => "UTF-8" } }) ])
        .to eq([ "users: file.csv.col_sep must be a non-empty string", "users: file.csv has unknown keys: encoding" ])
    end
  end

  describe "file.xlsx" do
    it "defaults to no options and accepts sheet" do
      expect([ definition.file[:xlsx], definition(file: { "xlsx" => { "sheet" => "Data" } }).file[:xlsx] ])
        .to eq([ {}, { sheet: "Data" } ])
    end

    it "rejects unknown keys" do
      expect(config_error(file: { "xlsx" => { "range" => "A1" } })).to eq("users: file.xlsx has unknown keys: range")
    end
  end

  describe "columns" do
    it "uses the column key as header when header is absent" do
      expect(outcome("email\na@x.io\n", columns: { "email" => nil })).to eq(ok(email: "a@x.io"))
    end

    it "matches header and aliases (one or a list), ignoring case and spacing" do
      columns = { "email" => { "header" => "Email", "aliases" => "Mail" }, "name" => { "aliases" => [ "Full name", "Tên" ] } }

      expect([ outcome("MAIL ,  full  NAME\na@x.io,Ann\n", columns:), outcome("email,tên\na@x.io,Ann\n", columns:) ])
        .to all(eq(ok(ann)))
    end

    it "matches header_pattern when no name matches" do
      columns = { "email" => { "header_pattern" => '\Ae-?mail' }, "name" => { "header_pattern" => [ "name", '\Afull' ] } }

      expect(outcome("E-mail address,Full\na@x.io,Ann\n", columns:)).to eq(ok(ann))
    end

    it "requires a header only for required columns" do
      columns = { "email" => { "required" => true }, "name" => { "required" => false } }

      expect([ outcome("email\na@x.io\n", columns:), outcome("name\nAnn\n", columns:) ])
        .to eq([ ok(email: "a@x.io", name: nil), failed(:missing_headers) ])
    end

    it "rejects missing columns, bad keys and duplicated headers" do
      expect([ config_error(columns: {}), config_error(columns: { "Email" => nil }),
        config_error(columns: { "a" => { "header" => "X" }, "b" => { "aliases" => [ " x " ] } }) ])
        .to eq([ "users: columns must define at least one column", "users: columns.Email must be snake_case",
          "users: columns header \"x\" is used more than once" ])
    end
  end

  describe "column types" do
    def cast(type, value, **options)
      column = { "header" => "Value", **(type ? { "type" => type } : {}), **options }
      result = run("Value\n#{value}\n", columns: { "value" => column }, on_error: "skip")
      result.errors.any? ? result.errors.map { |e| [ e.code, e.message ] } : result.records.first[:value]
    end

    it "keeps strings by default (type absent or string)" do
      expect([ cast(nil, "abc"), cast("string", "abc") ]).to eq(%w[ abc abc ])
    end

    it "casts integer, decimal and boolean" do
      expect([ cast("integer", "42"), cast("decimal", "1.5"), cast("boolean", "yes"), cast("boolean", "0") ])
        .to eq([ 42, BigDecimal("1.5"), true, false ])
    end

    it "reports values that cannot be cast" do
      expect([ cast("integer", "1.5"), cast("decimal", "x"), cast("boolean", "maybe") ]).to eq([
        [ [ :invalid_type, "Value must be an integer" ] ], [ [ :invalid_type, "Value must be a number" ] ],
        [ [ :invalid_type, "Value must be true or false" ] ]
      ])
    end

    it "parses dates and times strictly with date_format" do
      expect([ cast("date", "01/02/2026", "date_format" => "%d/%m/%Y"),
        cast("datetime", "01/02/2026 10:30", "date_format" => "%d/%m/%Y %H:%M"),
        cast("date", "2026-02-01", "date_format" => "%d/%m/%Y") ])
        .to eq([ Date.new(2026, 2, 1), Time.zone.local(2026, 2, 1, 10, 30), [ [ :invalid_type, "Value must be a date" ] ] ])
      expect(log.string).not_to include("date_format")
    end

    it "parses ISO 8601 without date_format, else leniently with a warning" do
      expect([ cast("date", "2026-02-01"), cast("date", "1 Feb 2026"), cast("datetime", "Feb 1 2026 10:30") ])
        .to eq([ Date.new(2026, 2, 1), Date.new(2026, 2, 1), Time.zone.local(2026, 2, 1, 10, 30) ])
      expect(log.string.scan("has no date_format").size).to eq(2)
    end

    it "uses a custom caster from the column caster option, type describing the result" do
      stub_const("CentsCaster", Class.new(ApplicationImport::Casters::Base) do
        define_method(:call) { |value| (BigDecimal(value.to_s.delete("$")) * 100).to_i }
      end)

      expect([ cast("integer", "$1.50", "caster" => "CentsCaster"), cast("integer", "$1.50", "caster" => "CentsCaster", "max" => 100) ])
        .to eq([ 150, [ [ :too_big, "Value must be less than or equal to 100" ] ] ])
    end

    it "rejects a caster that is not a Casters::Base" do
      expect { definition(columns: { "value" => { "caster" => "String" } }) }
        .to raise_error(ApplicationImport::Errors::InvalidCasterError)
    end

    it "turns blank cells into nil" do
      expect(run("Email,Name\na@x.io,\n").records).to eq([ { email: "a@x.io", name: nil } ])
    end
  end

  describe "column rules" do
    # A second column keeps the row from being blank when value is empty.
    def check(value, type: "string", **options)
      columns = { "value" => { "header" => "Value", "type" => type, **options }, "other" => { "header" => "Other" } }
      run("Value,Other\n#{value},x\n", columns:, on_error: "skip").errors.map(&:code)
    end

    it "requires a value with required: true only" do
      expect([ check("", "required" => true), check(""), check("", "required" => false), check("x", "required" => true) ])
        .to eq([ %i[ required ], [], [], [] ])
    end

    it "checks min_length / max_length" do
      expect([ check("a", "min_length" => 2), check("abcd", "max_length" => 3), check("ab", "min_length" => 2, "max_length" => 3) ])
        .to eq([ %i[ too_short ], %i[ too_long ], [] ])
    end

    it "checks min / max on numbers and dates" do
      expect([ check("17", :type => "integer", "min" => 18), check("151", :type => "integer", "max" => 150),
        check("1999-12-31", :type => "date", "min" => "2000-01-01"), check("20", :type => "integer", "min" => 18, "max" => 150) ])
        .to eq([ %i[ too_small ], %i[ too_big ], %i[ too_small ], [] ])
    end

    it "checks format (regexp or email)" do
      expect([ check("1a", "format" => '\A\d+\z'), check("nope", "format" => "email"), check("a@x.io", "format" => "email") ])
        .to eq([ %i[ invalid_format ], %i[ invalid_format ], [] ])
    end

    it "checks inclusion" do
      expect([ check("guest", "inclusion" => %w[ admin member ]), check("admin", "inclusion" => %w[ admin member ]) ])
        .to eq([ %i[ not_included ], [] ])
    end

    it "skips rules for a value that could not be cast" do
      expect(check("x", :type => "integer", "min" => 1)).to eq(%i[ invalid_type ])
    end
  end

  describe "transformers" do
    def with(transformers, content = "Email,Name\n A@X.IO ,Ann\n", **config)
      outcome(content, transformers:, **config)
    end

    it "runs none when absent, empty or null" do
      expect([ outcome, with([], "Email,Name\na@x.io,Ann\n"), with(nil, "Email,Name\na@x.io,Ann\n") ]).to all(eq(ok(ann)))
    end

    it "runs built-in transformers in order" do
      transformers = [
        { "type" => "normalize", "attributes" => [ "email" ], "with" => %w[ strip downcase ] },
        { "type" => "default", "attribute" => "role", "value" => "member" },
        { "type" => "map", "attribute" => "name", "values" => { "Ann" => "Annabelle" } },
        { "type" => "concat", "from" => %w[ name email ], "to" => "label", "separator" => " <" },
        { "type" => "context", "key" => "user_id", "to" => "created_by_id" }
      ]
      result = ApplicationImport.run(definition(transformers:), StringIO.new("Email,Name\n A@X.IO ,Ann\n"), filename: "users.csv",
        runner: "ConfigSpecRunner", logger:, context: { user_id: 9 })

      expect(result.records).to eq([
        { email: "a@x.io", name: "Annabelle", role: "member", label: "Annabelle <a@x.io", created_by_id: 9 }
      ])
    end

    it "runs custom transformer classes with their options" do
      stub_const("Initials", Class.new(ApplicationImport::Transformers::Base) do
        define_method(:call) { |attributes, _row| { initials: attributes[:name][0, options[:size]].upcase } }
      end)

      expect(with([ { "class" => "Initials", "size" => 2 } ]).last).to eq([ { email: " A@X.IO ", name: "Ann", initials: "AN" } ])
    end

    it "turns map strict misses into not_mapped row errors" do
      transformers = [ { "type" => "map", "attribute" => "name", "values" => { "Bob" => "B" }, "strict" => true } ]

      expect(with(transformers, on_error: "skip").first(2)).to eq([ :completed_with_errors, %i[ not_mapped ] ])
    end

    it "rejects invalid transformer settings" do
      expect([ config_error(transformers: { "type" => "concat" }), config_error(transformers: [ { "type" => "upper" } ]),
        config_error(transformers: [ { "class" => "String" } ]) ])
        .to eq([ "users: transformers must be a list", "users: transformers[0].type must be one of concat, default, map, normalize, context",
          "String must inherit from ApplicationImport::Transformers::Base" ])
    end
  end

  describe "mapper" do
    before do
      ActiveRecord::Base.connection.create_table(:mapper_spec_users, temporary: true) do |t|
        t.string :user_email
        t.string :full_name
      end
      stub_const("MapperSpecUser", Class.new(ApplicationRecord) { self.table_name = "mapper_spec_users" })
    end

    def records(mapper)
      captured = []
      stub_const("RecordRunner", Class.new(ApplicationImport::Runner) { define_method(:write_rows) { captured.concat(rows) } })
      ApplicationImport.run(definition(mapper:, output: { "model" => "MapperSpecUser" }), StringIO.new("Email,Name\na@x.io,Ann\n"),
        filename: "users.csv", runner: "RecordRunner", logger:)
      captured
    end

    it "is optional" do
      expect(outcome).to eq(ok(ann))
    end

    it "renames attributes so the record gets them" do
      row = records({ "type" => "rename", "attributes" => { "email" => "user_email", "name" => "full_name" } }).first

      expect([ row.attributes, row.record.user_email, row.record.full_name ])
        .to eq([ { user_email: "a@x.io", full_name: "Ann" }, "a@x.io", "Ann" ])
    end

    it "keeps only renamed attributes with only" do
      row = records({ "type" => "rename", "attributes" => { "email" => "user_email" }, "only" => true }).first

      expect(row.attributes).to eq(user_email: "a@x.io")
    end

    it "runs a custom mapper class" do
      stub_const("UpcaseMapper", Class.new(ApplicationImport::Mappers::Base) do
        define_method(:call) { |attributes, _row| { user_email: attributes[:email].upcase } }
      end)

      expect(records({ "class" => "UpcaseMapper" }).first.record.user_email).to eq("A@X.IO")
    end

    it "rejects invalid settings" do
      expect([ config_error(mapper: { "type" => "split" }), config_error(mapper: { "class" => "String" }) ])
        .to eq([ "users: mapper.type must be one of rename", "String must inherit from ApplicationImport::Mappers::Base" ])
    end
  end

  describe "validators" do
    it "runs with no validators section, an empty one, or a null one" do
      expect([ outcome, outcome(validators: {}), outcome(validators: nil) ]).to all(eq(ok(ann)))
    end

    %w[ file row rows verify ].each do |stage|
      it "runs with an empty or null #{stage} stage" do
        expect([ outcome(validators: { stage => [] }), outcome(validators: { stage => nil }) ]).to all(eq(ok(ann)))
      end
    end

    it "runs with every stage empty" do
      expect(outcome(validators: { "file" => [], "row" => [], "rows" => [], "verify" => [] })).to eq(ok(ann))
    end

    describe "type: model" do
      before do
        ActiveRecord::Base.connection.create_table(:config_spec_users, temporary: true) { |t| t.string :email }
        stub_const("ConfigSpecUser", Class.new(ApplicationRecord) do
          self.table_name = "config_spec_users"
          validates :email, format: { with: /@/ }, uniqueness: true
        end)
        ConfigSpecUser.create!(email: "a@x.io")
      end

      def model_run(content, **validator)
        result = run(content, validators: { "row" => [ { "type" => "model", **validator } ] }, output: { "model" => "ConfigSpecUser" },
          on_error: "skip")
        [ result.status, result.errors.map { |e| [ e.line, e.code, e.column ] }, result.records ]
      end

      it "runs the model validations on each row (output.model)" do
        expect(model_run("Email,Name\na@x.io,Ann\nnope,Bob\nb@x.io,Cy\n")).to eq([
          :completed_with_errors, [ [ 2, :taken, "email" ], [ 3, :invalid, "email" ] ], [ { email: "b@x.io", name: "Cy" } ]
        ])
      end

      it "ignores the kinds listed in except" do
        expect(model_run("Email,Name\na@x.io,Ann\n", "except" => [ "uniqueness" ])).to eq(ok(ann))
      end

      it "requires a model" do
        expect(config_error(validators: { "row" => [ { "type" => "model" } ] }))
          .to eq("users: validators.row[0].model is required without output.model")
      end
    end

    describe "type: unique_in_file" do
      let(:content) { "Email,Name\na@x.io,Ann\nA@X.IO,Bob\na@x.io,Cy\n" }

      def unique_run(**options)
        run(content, validators: { "rows" => [ { "type" => "unique_in_file", "keys" => [ "email" ], **options } ] }, on_error: "skip")
          .then { |result| [ result.errors.map { |e| [ e.line, e.code ] }, result.records.map { |r| r[:name] } ] }
      end

      it "flags repeated keys, case-sensitively by default" do
        expect(unique_run).to eq([ [ [ 4, :duplicate ] ], %w[ Ann Bob ] ])
      end

      it "ignores case with case_sensitive: false" do
        expect(unique_run("case_sensitive" => false)).to eq([ [ [ 3, :duplicate ], [ 4, :duplicate ] ], %w[ Ann ] ])
      end

      it "uses names produced by the mapper" do
        result = run("Email,Name\na@x.io,Ann\na@x.io,Bob\n", mapper: { "type" => "rename", "attributes" => { "email" => "user_email" } },
          validators: { "rows" => [ { "type" => "unique_in_file", "keys" => [ "user_email" ] } ] }, on_error: "skip")

        expect(result.errors.map { |e| [ e.line, e.code ] }).to eq([ [ 3, :duplicate ] ])
      end

      it "fails the run when a key is missing from the attributes at run time" do
        definition = definition(mapper: { "type" => "rename", "attributes" => { "email" => "user_email" } },
          validators: { "rows" => [ { "type" => "unique_in_file", "keys" => [ "email" ] } ] })
        runner = ConfigSpecRunner.new(definition, ApplicationImport::Source.build(StringIO.new("Email,Name\na@x.io,Ann\n"), filename: "u.csv"),
          logger:)

        expect { runner.call }.to raise_error(ApplicationImport::Errors::ConfigError, /unique_in_file keys not in the row attributes: email/)
        expect([ runner.result.status, runner.result.errors.map(&:code) ]).to eq([ :failed, [ :unexpected_error ] ])
      end

      it "rejects unknown key columns" do
        expect(config_error(validators: { "rows" => [ { "type" => "unique_in_file", "keys" => [ "phone" ] } ] }))
          .to eq("users: validators.rows[0].keys references unknown columns: phone")
      end
    end

    it "builds custom validators with their options, the run's context and logger" do
      seen = []
      stub_const("ContextValidator", Class.new(ApplicationImport::Validators::RowValidator) do
        define_method(:call) { |_row, _result| seen << [ options, context, logger ] }
      end)

      ApplicationImport.run(definition(validators: { "row" => [ { "class" => "ContextValidator", "limit" => 3 } ] }),
        StringIO.new("Email,Name\na@x.io,Ann\n"), filename: "u.csv", runner: "ConfigSpecRunner", logger:, context: { user_id: 7 })

      expect(seen).to eq([ [ { limit: 3 }, { user_id: 7 }, logger ] ])
    end

    it "rejects a stage that is not a list" do
      expect(config_error(validators: { "row" => {} })).to eq("users: validators.row must be a list")
    end
  end

  describe "on_error.row_errors" do
    before do
      stub_const("TwoChecksA", Class.new(ApplicationImport::Validators::RowValidator) do
        define_method(:call) { |row, _result| row.add_error(code: :a, message: "a") }
      end)
      stub_const("TwoChecksB", Class.new(ApplicationImport::Validators::RowValidator) do
        define_method(:call) { |row, _result| row.add_error(code: :b, message: "b") }
      end)
    end

    def codes(on_error)
      run(validators: { "row" => [ { "class" => "TwoChecksA" }, { "class" => "TwoChecksB" } ] }, on_error:).errors.map(&:code)
    end

    it "stops each row at its first failing check when absent or first" do
      expect([ codes("skip"), codes({ "default" => "skip" }), codes({ "default" => "skip", "row_errors" => "first" }) ])
        .to all(eq(%i[ a ]))
    end

    it "collects every error of the row with all" do
      expect(codes({ "default" => "skip", "row_errors" => "all" })).to eq(%i[ a b ])
    end

    it "rejects other values" do
      expect(config_error(on_error: { "row_errors" => "none" })).to eq("users: on_error.row_errors must be one of first, all")
    end
  end

  describe "output" do
    before do
      ActiveRecord::Base.connection.create_table(:output_spec_users, temporary: true) do |t|
        t.string :email
        t.string :name
        t.index :email, unique: true
      end
      stub_const("OutputSpecUser", Class.new(ApplicationRecord) do
        self.table_name = "output_spec_users"
        validates :name, presence: true
      end)
    end

    let(:content) { "Email,Name\na@x.io,Ann\nb@x.io,\nc@x.io,Cy\n" }

    # Uses the real writers (no runner override).
    def write(output, on_error: "skip", content: self.content)
      definition = definition(output:, on_error:)
      ApplicationImport.run(definition, StringIO.new(content), filename: "users.csv", logger:)
    end

    def summary(result)
      [ result.status, result.errors.map { |e| [ e.line, e.code ] }, result.stats.values_at(:total, :valid, :invalid, :written),
        OutputSpecUser.order(:email).pluck(:email) ]
    end

    it "returns attributes without touching the database by default (no model)" do
      result = write({})

      expect([ result.status, result.records.size, OutputSpecUser.count ]).to eq([ :completed, 3, 0 ])
    end

    it "imports with activerecord-import by default when a model is set" do
      expect(summary(write({ "model" => "OutputSpecUser" }))).to eq([
        :completed_with_errors, [ [ 3, :not_saved ] ], [ 3, 3, 1, 2 ], %w[ a@x.io c@x.io ]
      ])
    end

    it "saves record by record with mode save" do
      expect(summary(write({ "model" => "OutputSpecUser", "mode" => "save" }))).to eq([
        :completed_with_errors, [ [ 3, :not_saved ] ], [ 3, 3, 1, 2 ], %w[ a@x.io c@x.io ]
      ])
    end

    it "rolls the whole write back and fails on abort (transaction by default)" do
      %w[ bulk save ].each do |mode|
        expect(summary(write({ "model" => "OutputSpecUser", "mode" => mode }, on_error: "abort")))
          .to eq([ :failed, [ [ 3, :not_saved ] ], [ 3, 3, 1, 0 ], [] ])
      end
    end

    it "keeps what was written before the abort without transaction" do
      result = write({ "model" => "OutputSpecUser", "mode" => "save", "transaction" => false }, on_error: "abort")

      expect(summary(result)).to eq([ :failed, [ [ 3, :not_saved ] ], [ 3, 3, 1, 1 ], %w[ a@x.io ] ])
    end

    it "does not write rows skipped before the write" do
      columns = { "email" => { "header" => "Email", "required" => true }, "name" => { "header" => "Name" } }
      result = ApplicationImport.run(definition(columns:, output: { "model" => "OutputSpecUser" }, on_error: "skip"),
        StringIO.new("Email,Name\na@x.io,Ann\n,Bob\n"), filename: "users.csv", logger:)

      expect(summary(result)).to eq([ :completed_with_errors, [ [ 3, :required ] ], [ 2, 1, 1, 1 ], %w[ a@x.io ] ])
    end

    it "upserts and passes import options" do
      OutputSpecUser.create!(email: "a@x.io", name: "Old")
      output = { "model" => "OutputSpecUser", "upsert" => { "conflict_target" => [ "email" ], "update" => [ "name" ] } }

      write(output, content: "Email,Name\na@x.io,New\n")

      expect(OutputSpecUser.pluck(:name)).to eq([ "New" ])
    end

    it "passes save options" do
      write({ "model" => "OutputSpecUser", "mode" => "save", "save" => { "validate" => false } })

      expect(OutputSpecUser.count).to eq(3)
    end

    it "logs a summary at the end" do
      write({ "model" => "OutputSpecUser" })

      expect(log.string).to include("finished users.csv: completed_with_errors, total 3, valid 3, invalid 1, written 2")
    end

    it "rejects invalid output settings" do
      expect([ config_error(output: { "mode" => "database" }), config_error(output: { "mode" => "save" }),
        config_error(output: { "model" => "OutputSpecUser", "mode" => "save", "import" => {} }),
        config_error(output: { "model" => "OutputSpecUser", "transaction" => "yes" }) ])
        .to eq([ "users: output.mode must be one of raw, save, bulk", "users: output.model is required when mode is save",
          "users: output.import is only used when mode is bulk", "users: output.transaction must be true or false" ])
    end
  end

  describe "settings defaults" do
    after { ApplicationImport.reset_configuration! }

    def build(config)
      ApplicationImport::Definition.build(:users, { "columns" => default_columns }.merge(config))
    end

    it "applies nothing without defaults" do
      expect(build({}).file[:formats]).to be_nil
    end

    it "fills settings the definition leaves out and lets the definition win" do
      ApplicationImport.configure { |config| config.defaults = { file: { formats: [ "csv" ], unknown_headers: "reject" } } }

      expect([ build({}).file.values_at(:formats, :unknown_headers), build("file" => { "unknown_headers" => "keep" }).file[:unknown_headers] ])
        .to eq([ [ %i[ csv ], :reject ], :keep ])
    end

    it "validates defaults like the definition itself" do
      ApplicationImport.configure { |config| config.defaults = { file: { headers: "yes" } } }

      expect { build({}) }.to raise_error(ApplicationImport::Errors::ConfigError, "users: file.headers must be true or false")
    end
  end
end
