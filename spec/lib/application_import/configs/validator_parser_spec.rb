RSpec.describe ApplicationImport::Configs::ValidatorParser do
  let(:errors) { [] }

  def parse(config)
    described_class.new(config, %i[ email name ], errors).parse
  end

  it "parses registered and class validators" do
    result = parse([
      { "type" => "unique_in_file", "keys" => [ "email" ], "case_sensitive" => false },
      { "class" => "Imports::DomainValidator", "scope" => "row", "allowed" => [ "a.com" ] }
    ])

    expect(result).to eq([
      { type: :unique_in_file, class: nil, scope: :file, options: { keys: [ :email ], case_sensitive: false } },
      { type: nil, class: "Imports::DomainValidator", scope: :row, options: { allowed: [ "a.com" ] } }
    ])
    expect(errors).to be_empty
  end

  it "requires a list of mappings" do
    expect([ parse({}), parse([ "unique_in_file" ]) ]).to eq([ [], [] ])
    expect(errors).to eq([ "validators must be a list", "validators[0] must be a mapping" ])
  end

  it "requires exactly one of type and class" do
    parse([ {}, { "type" => "unique_in_file", "class" => "X" } ])

    expect(errors).to eq([
      "validators[0] needs exactly one of type, class",
      "validators[1] needs exactly one of type, class"
    ])
  end

  it "rejects unknown types and scopes" do
    parse([ { "type" => "exists", "scope" => "batch" } ])

    expect(errors).to eq([
      "validators[0].type must be one of unique_in_file",
      "validators[0].scope must be one of file, row"
    ])
  end

  it "checks unique_in_file options" do
    parse([ { "type" => "unique_in_file", "keys" => [ "phone" ], "scope" => "row", "strict" => true, "case_sensitive" => "no" } ])

    expect(errors).to contain_exactly(
      "validators[0].scope must be file for unique_in_file",
      "validators[0] has unknown keys: strict",
      "validators[0].keys references unknown columns: phone",
      "validators[0].case_sensitive must be true or false"
    )
  end

  it "requires unique_in_file keys" do
    parse([ { "type" => "unique_in_file" } ])

    expect(errors).to eq([ "validators[0].keys must be a non-empty list of names" ])
  end
end
