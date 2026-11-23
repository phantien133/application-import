RSpec.describe ApplicationImport::Result do
  subject(:result) { described_class.new }

  it "starts empty and completed" do
    expect([ result.records, result.errors, result.stats, result.status ])
      .to eq([ [], [], { total: 0, valid: 0, invalid: 0, written: 0 }, :completed ])
  end

  it "adds file and row errors" do
    result.add_file_error(:too_large, "file is too large")
      .add_row_error(line: 3, column: :email, code: :required, message: "Email is required")

    expect(result.errors.map(&:to_h)).to eq([
      { code: :too_large, message: "file is too large" },
      { line: 3, column: "email", code: :required, message: "Email is required" }
    ])
  end

  describe "#add_exception" do
    it "adds a FileError as a file-level error" do
      result.add_exception(ApplicationImport::Errors::FileError.new("bad bytes", code: :invalid_encoding))

      expect(result.errors.map(&:to_h)).to eq([ { code: :invalid_encoding, message: "bad bytes" } ])
    end

    it "adds a RowError on its line and column" do
      result.add_exception(ApplicationImport::Errors::RowError.new("Email is required", line: 3, column: :email, code: :required))

      expect(result.errors.map(&:to_h)).to eq([ { line: 3, column: "email", code: :required, message: "Email is required" } ])
    end

    it "adds a RowsError on its first line with every line in details" do
      error = ApplicationImport::Errors::RowsError.new("duplicate email", lines: [ 2, 5 ], columns: [ :email ], code: :duplicate)
      result.add_exception(error)

      expect(result.errors.map(&:to_h)).to eq([
        { line: 2, column: "email", code: :duplicate, message: "duplicate email",
          details: { lines: [ 2, 5 ], columns: [ "email" ] } }
      ])
    end

    it "rejects other exceptions" do
      expect { result.add_exception(RuntimeError.new("boom")) }.to raise_error(ArgumentError, "unsupported error: RuntimeError")
    end
  end

  it "detects file-level errors" do
    result.add_row_error(line: 2, column: :email, code: :required, message: "x")
    expect(result.file_errors?).to be(false)

    result.add_file_error(:empty_file, "file is empty")
    expect(result.file_errors?).to be(true)
  end

  it "accumulates records and stats" do
    result.add_records([ { id: 1 } ]).add_records([ { id: 2 } ]).increment(:total, 2).increment(:written)

    expect([ result.records, result.stats ]).to eq([ [ { id: 1 }, { id: 2 } ], { total: 2, valid: 0, invalid: 0, written: 1 } ])
  end

  describe "#status" do
    it "is completed_with_errors when errors exist without halting" do
      result.add_row_error(line: 2, column: :email, code: :required, message: "x")

      expect([ result.status, result.success?, result.failed? ]).to eq([ :completed_with_errors, false, false ])
    end

    it "is failed once halted" do
      result.halt!

      expect([ result.halted?, result.status, result.success?, result.failed? ]).to eq([ true, :failed, false, true ])
    end
  end

  it "is not a dry run by default" do
    expect([ described_class.new.dry_run?, described_class.new(dry_run: true).dry_run? ]).to eq([ false, true ])
  end

  it "serializes to a hash" do
    result.add_file_error(:empty_file, "file is empty").add_records([ { id: 1 } ]).halt!

    expect(result.to_h).to eq(
      status: :failed, dry_run: false, stats: { total: 0, valid: 0, invalid: 0, written: 0 },
      errors: [ { code: :empty_file, message: "file is empty" } ], records: [ { id: 1 } ]
    )
  end
end
