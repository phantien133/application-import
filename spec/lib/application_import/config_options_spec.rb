# End-to-end behaviour of every definition option implemented so far, run through
# ApplicationImport.run: option absent, each accepted value, and invalid values.
# Parsing details live in spec/lib/application_import/configs/*_parser_spec.rb.
RSpec.describe "ApplicationImport config options" do # rubocop:disable RSpec/DescribeClass
  let(:log) { StringIO.new }
  let(:logger) { ActiveSupport::Logger.new(log).tap { |l| l.formatter = ->(severity, _, _, msg) { "#{severity} #{msg}\n" } } }

  before do
    stub_const("ConfigSpecRunner", Class.new(ApplicationImport::Runner) do
      def process
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
      expect(config_error(file: { "unknown_headers" => "drop" })).to eq("users: file.unknown_headers must be one of skip, keep, reject")
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
