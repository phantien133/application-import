RSpec.describe ApplicationImport::ErrorEntry do
  it "builds row entries" do
    entry = described_class.new(line: 3, column: :email, code: :required, message: "Email is required")

    expect(entry.file_level?).to be(false)
    expect(entry.to_h).to eq(line: 3, column: "email", code: :required, message: "Email is required")
  end

  it "keeps details" do
    entry = described_class.new(line: 2, code: :duplicate, message: "duplicate", details: { lines: [ 2, 5 ] })

    expect(entry.to_h).to eq(line: 2, code: :duplicate, message: "duplicate", details: { lines: [ 2, 5 ] })
  end

  it "builds file-level entries without line and column" do
    entry = described_class.for_file(:too_large, "file is too large")

    expect(entry.file_level?).to be(true)
    expect(entry.to_h).to eq(code: :too_large, message: "file is too large")
  end
end
