RSpec.describe ApplicationImport::Configs::OnErrorParser do
  let(:errors) { [] }

  def parse(config)
    described_class.new(config, errors).parse
  end

  it "defaults to abort" do
    expect(parse(nil)).to eq(ApplicationImport::ErrorPolicy.new(default: :abort))
  end

  it "accepts the short form" do
    expect([ parse("skip").default, parse(:abort).default ]).to eq(%i[ skip abort ])
  end

  it "parses default, allow and skip codes" do
    policy = parse({ "default" => "skip", "allow" => [ "duplicate" ], "skip" => [ "required", "invalid_type" ] })

    expect(policy).to eq(ApplicationImport::ErrorPolicy.new(default: :skip, allow: %i[ duplicate ], skip: %i[ required invalid_type ]))
    expect(errors).to be_empty
  end

  it "defaults the mapping form to abort" do
    expect(parse({ "allow" => [ "duplicate" ] }).default).to eq(:abort)
  end

  it "reports invalid values" do
    parse("ignore")
    parse({ "default" => "allow", "skip" => [], "extra" => 1 })

    expect(errors).to eq([
      "on_error must be one of abort, skip",
      "on_error has unknown keys: extra",
      "on_error.skip must be a non-empty list of names",
      "on_error.default must be one of abort, skip"
    ])
  end

  it "rejects codes listed in both allow and skip" do
    parse({ "allow" => [ "duplicate", "required" ], "skip" => [ "required" ] })

    expect(errors).to eq([ "on_error lists codes in both allow and skip: required" ])
  end
end
