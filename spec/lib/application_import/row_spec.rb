RSpec.describe ApplicationImport::Row do
  subject(:row) { described_class.new(line: 3, attributes: { email: "a" }, raw: [ "a" ]) }

  it "exposes line, attributes, raw and an empty state" do
    expect([ row.line, row.attributes, row.raw, row.record, row.errors, row.errors?, row.skipped? ])
      .to eq([ 3, { email: "a" }, [ "a" ], nil, [], false, false ])
  end

  it "lets the pipeline replace attributes and set the record" do
    row.attributes = { email: "b" }
    row.record = :record

    expect([ row.attributes, row.record ]).to eq([ { email: "b" }, :record ])
  end

  describe "#add_error" do
    it "adds an error entry on the row line and returns the row" do
      expect(row.add_error(code: "required", message: "Email is required", column: :email, details: { a: 1 })).to be(row)
      expect(row.errors).to eq([
        ApplicationImport::ErrorEntry.new(line: 3, column: "email", code: :required, message: "Email is required", details: { a: 1 })
      ])
      expect(row.errors?).to be(true)
    end
  end

  describe "#take_new_errors" do
    it "returns only the errors added since the last call" do
      row.add_error(code: :a, message: "a")
      first = row.take_new_errors
      row.add_error(code: :b, message: "b").add_error(code: :c, message: "c")

      expect([ first.map(&:code), row.take_new_errors.map(&:code), row.take_new_errors ]).to eq([ %i[ a ], %i[ b c ], [] ])
      expect(row.errors.map(&:code)).to eq(%i[ a b c ])
    end
  end

  it "can be skipped" do
    expect(row.skip!).to be(row)
    expect(row.skipped?).to be(true)
  end

  it "compares by value" do
    other = described_class.new(line: 3, attributes: { email: "a" }, raw: [ "a" ])

    expect(row).to eq(other)
    expect(row).not_to eq(other.add_error(code: :x, message: "x"))
    expect(row).not_to eq(described_class.new(line: 3, attributes: { email: "a" }, raw: [ "a" ]).skip!)
  end
end
