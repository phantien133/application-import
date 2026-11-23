RSpec.describe ApplicationImport::Readers::RawRow do
  subject(:row) { described_class.new(line: 2, values: [ "a@example.com", "Ann" ]) }

  it "maps values to headers by position" do
    expect(row.to_h(%w[ Email Name ])).to eq("Email" => "a@example.com", "Name" => "Ann")
  end

  it "fills missing cells with nil and drops extra cells" do
    expect([ row.to_h(%w[ Email Name Age ]), row.to_h(%w[ Email ]) ])
      .to eq([ { "Email" => "a@example.com", "Name" => "Ann", "Age" => nil }, { "Email" => "a@example.com" } ])
  end

  it "is an immutable value object" do
    expect(row).to be_frozen
    expect(row).to eq(described_class.new(line: 2, values: [ "a@example.com", "Ann" ]))
  end

  it "maps to an empty hash without headers" do
    expect(row.to_h([])).to eq({})
  end

  it "keeps the last value for duplicate headers" do
    expect(row.to_h(%w[ Email Email ])).to eq("Email" => "Ann")
  end
end
