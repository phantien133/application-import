RSpec.describe ApplicationImport::Casters::BooleanCaster do
  subject(:caster) { build_caster(type: :boolean, header: "Active") }

  it "maps true words case-insensitively, trimming spaces" do
    expect([ "true", "T", "Yes", "y", "1", " TRUE " ].map { |value| caster.call(value) }).to all(be(true))
  end

  it "maps false words case-insensitively" do
    expect([ "false", "F", "NO", "n", "0" ].map { |value| caster.call(value) }).to all(be(false))
  end

  it "keeps booleans and accepts 1 / 0 numbers" do
    expect([ caster.call(true), caster.call(false), caster.call(1), caster.call(0) ]).to eq([ true, false, true, false ])
  end

  it "reports other values as invalid, naming the column" do
    [ "maybe", "2", "on", "off" ].each do |value|
      expect { caster.call(value) }.to raise_error(ApplicationImport::Caster::Invalid, "Active must be true or false")
    end
  end

  it "lets a subclass change the words" do
    viet = Class.new(described_class) do
      const_set(:TRUE_VALUES, %w[ có ].freeze)
      const_set(:FALSE_VALUES, %w[ không ].freeze)
    end
    caster = viet.new(build_caster.column, definition: build_caster.definition)

    expect([ caster.call("Có"), caster.call("KHÔNG") ]).to eq([ true, false ])
    expect { caster.call("yes") }.to raise_error(ApplicationImport::Caster::Invalid)
  end
end
