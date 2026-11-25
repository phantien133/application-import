RSpec.describe Users::ImportService do
  def csv(*lines, name: "users.csv")
    file = Tempfile.new([ File.basename(name, ".*"), File.extname(name) ])
    file.write([ "Email,Name", *lines ].join("\n"))
    file.rewind
    file
  end

  it "imports the users and returns the result" do
    result = nil

    expect { result = described_class.call(csv("ann@example.com,Ann")) }.to change(User, :count).by(1)
    expect(result).to have_attributes(status: :completed, stats: include(written: 1))
  end

  it "returns completed_with_errors when rows are skipped" do
    result = described_class.call(csv("ann@example.com,Ann", "bad,Bob"))

    expect(result.status).to eq(:completed_with_errors)
    expect(result.errors.map(&:code)).to eq(%i[ invalid_format ])
  end

  it "writes nothing in a dry run" do
    result = nil

    expect { result = described_class.call(csv("ann@example.com,Ann"), dry_run: true) }.not_to change(User, :count)
    expect(result).to have_attributes(dry_run?: true, stats: include(valid: 1, written: 0))
  end

  it "raises ImportFailedError with the result when the import fails" do
    expect { described_class.call(csv("ann@example.com,Ann", name: "users.txt")) }.to raise_error(ImportFailedError) { |error|
      expect(error).to have_attributes(status: :unprocessable_content, code: :import_failed)
      expect(error.result).to be_failed
      expect(error.details.deep_symbolize_keys[:errors].first).to include(code: :invalid_format)
    }
  end
end
