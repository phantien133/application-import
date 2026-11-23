RSpec.describe ApplicationImport::Configs::MapperParser do
  let(:errors) { [] }

  def parse(config)
    described_class.new(config, errors).parse
  end

  it "is nil when absent" do
    expect(parse(nil)).to be_nil
  end

  it "parses a custom class with options" do
    expect(parse({ "class" => "Imports::UserMapper", "prefix" => "x" }))
      .to eq(type: nil, class: "Imports::UserMapper", options: { prefix: "x" })
  end

  it "parses type rename" do
    expect(parse({ "type" => "rename", "attributes" => { "email" => "user_email" }, "only" => true }))
      .to eq(type: :rename, class: "ApplicationImport::Mappers::Rename", options: { attributes: { email: :user_email }, only: true })
    expect(errors).to eq([])
  end

  it "reports invalid settings" do
    [ [], {}, { "type" => "rename", "class" => "X" }, { "type" => "split" }, { "class" => 1 }, { "class" => nil },
      { "type" => "rename", "attributes" => {}, "only" => "y", "extra" => 1 }, { "type" => "rename", "attributes" => { "a" => "" } } ]
      .each { |config| parse(config) }

    expect(errors).to eq([
      "mapper must be a mapping", "mapper needs exactly one of type, class", "mapper needs exactly one of type, class",
      "mapper.type must be one of rename", "mapper.class must be a class name", "mapper.class must be a class name",
      "mapper has unknown keys: extra", "mapper.only must be true or false", "mapper.attributes must be a non-empty mapping of names",
      "mapper.attributes must be a non-empty mapping of names"
    ])
  end

  describe ".resolve!" do
    it "resolves the class and rejects non mappers" do
      klass = stub_const("UserMapper", Class.new(ApplicationImport::Mappers::Base))
      spec = { class: "UserMapper" }

      described_class.resolve!(spec)

      expect(spec[:class]).to eq(klass)
      expect(described_class.resolve!(nil)).to be_nil
      expect { described_class.resolve!({ class: "String" }) }
        .to raise_error(ApplicationImport::Errors::InvalidMapperError, "String must inherit from ApplicationImport::Mappers::Base")
    end
  end
end
