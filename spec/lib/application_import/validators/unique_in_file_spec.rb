RSpec.describe ApplicationImport::Validators::UniqueInFile do
  let(:definition) do
    ApplicationImport::Definition.new(:users, { "columns" => { "email" => { "header" => "Email" }, "name" => { "header" => "Name" } } })
  end
  let(:result) { ApplicationImport::Result.new }

  def check(rows, **options)
    validator = described_class.new(definition, { keys: [ :email ], **options })
    rows.each_with_index.flat_map { |attributes, index| errors_after(validator, attributes, index + 2) }
  end

  def errors_after(validator, attributes, line)
    row = ApplicationImport::Row.new(line:, attributes:, raw: [])
    validator.call(row, result, {})
    row.errors.map { |error| [ error.line, error.code, error.column, error.message, error.details ] }
  end

  it "flags a row repeating the keys of an earlier row, pointing at the first line" do
    expect(check([ { email: "a@x.io" }, { email: "b@x.io" }, { email: "a@x.io" }, { email: "a@x.io" } ])).to eq([
      [ 4, :duplicate, "email", "Email duplicates line 2", { keys: [ :email ], line: 2 } ],
      [ 5, :duplicate, "email", "Email duplicates line 2", { keys: [ :email ], line: 2 } ]
    ])
  end

  it "compares case-sensitively by default" do
    expect(check([ { email: "a@x.io" }, { email: "A@X.IO" } ])).to eq([])
  end

  it "ignores case with case_sensitive: false" do
    expect(check([ { email: "a@x.io" }, { email: "A@X.IO" } ], case_sensitive: false).map(&:second)).to eq([ :duplicate ])
  end

  it "ignores surrounding spaces of String values" do
    expect(check([ { email: "a@x.io" }, { email: " a@x.io " } ]).size).to eq(1)
  end

  it "uses every key together" do
    rows = [ { email: "a", name: "x" }, { email: "a", name: "y" }, { email: "a", name: "x" } ]

    expect(check(rows, keys: %i[ email name ]).map { |error| [ error.first, error[3] ] }).to eq([ [ 4, "Email, Name duplicates line 2" ] ])
  end

  it "skips rows with a nil or blank key value" do
    rows = [ { email: nil }, { email: nil }, { email: "" }, { email: " " }, { email: "a", name: nil } ]

    expect([ check(rows), check([ { email: "a", name: nil }, { email: "a", name: nil } ], keys: %i[ email name ]) ]).to eq([ [], [] ])
  end

  it "compares non-String values as they are (eql?, so 1 and 1.0 differ)" do
    expect(check([ { email: 1 }, { email: 1 }, { email: 1.0 } ]).map(&:first)).to eq([ 3 ])
  end

  it "keeps its state per instance, so each run starts empty" do
    expect([ check([ { email: "a" } ]), check([ { email: "a" } ]) ]).to eq([ [], [] ])
  end

  it "raises ConfigError when a key is not in the row attributes (e.g. renamed by a mapper)" do
    row = ApplicationImport::Row.new(line: 2, attributes: { user_email: "a", name: "x" }, raw: [])
    validator = described_class.new(definition, { keys: %i[ email name ] })

    expect { validator.call(row, result, {}) }.to raise_error(ApplicationImport::Errors::ConfigError,
      "users: unique_in_file keys not in the row attributes: email (attributes: user_email, name)")
  end

  it "accepts a key present with a nil value" do
    row = ApplicationImport::Row.new(line: 2, attributes: { email: nil }, raw: [])

    expect { described_class.new(definition, { keys: [ :email ] }).call(row, result, {}) }.not_to raise_error
  end

  it "exposes keys and case_sensitive" do
    validator = described_class.new(definition, { keys: [ :email ], case_sensitive: false })

    expect([ validator.keys, validator.case_sensitive?, described_class.new(definition, { keys: [ :email ] }).case_sensitive? ])
      .to eq([ [ :email ], false, true ])
  end

  describe "rows with errors" do
    let(:definition) do
      ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil, "name" => nil }, "on_error" => { "allow" => [ "minor" ] } })
    end

    def errored(line, code)
      ApplicationImport::Row.new(line:, attributes: { email: "a" }, raw: []).add_error(code:, message: "x")
    end

    it "neither checks nor remembers a row with an error that is not allowed" do
      validator = described_class.new(definition, { keys: [ :email ] })
      dropped = errored(2, :required)
      later = ApplicationImport::Row.new(line: 3, attributes: { email: "a" }, raw: [])
      [ dropped, later ].each { |row| validator.call(row, result, {}) }

      expect([ dropped.errors.map(&:code), later.errors ]).to eq([ %i[ required ], [] ])
    end

    it "still checks rows whose errors are all allowed (they are written)" do
      validator = described_class.new(definition, { keys: [ :email ] })
      first = ApplicationImport::Row.new(line: 2, attributes: { email: "a" }, raw: [])
      allowed = errored(3, :minor)
      [ first, allowed ].each { |row| validator.call(row, result, {}) }

      expect(allowed.errors.map(&:code)).to eq(%i[ minor duplicate ])
    end
  end
end
