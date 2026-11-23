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

  describe "max_errors" do
    it "is nil (no limit) unless given" do
      expect([ parse(nil).max_errors, parse("skip").max_errors, parse({ "default" => "skip" }).max_errors,
        parse({ "max_errors" => nil }).max_errors ]).to all(be_nil)
    end

    it "accepts an integer >= 1" do
      expect(parse({ "max_errors" => 100 }).max_errors).to eq(100)
      expect(errors).to be_empty
    end

    it "rejects other values" do
      parse({ "max_errors" => 0 })
      parse({ "max_errors" => "10" })

      expect(errors).to eq([ "on_error.max_errors must be an integer >= 1" ] * 2)
    end
  end

  describe "row_errors" do
    it "defaults to first in both forms" do
      expect([ parse(nil).row_errors, parse("skip").row_errors, parse({ "default" => "skip" }).row_errors ]).to all(eq(:first))
    end

    it "accepts first and all" do
      expect([ parse({ "row_errors" => "first" }).row_errors, parse({ "row_errors" => "all" }).row_errors ]).to eq(%i[ first all ])
      expect(errors).to be_empty
    end

    it "rejects other values" do
      expect(parse({ "row_errors" => "some" }).row_errors).to eq(:first)
      expect(errors).to eq([ "on_error.row_errors must be one of first, all" ])
    end
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
