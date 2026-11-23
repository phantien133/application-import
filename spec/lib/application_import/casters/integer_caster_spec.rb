RSpec.describe ApplicationImport::Casters::IntegerCaster do
  subject(:caster) { build_caster(type: :integer) }

  it "parses base-10 integers, signs, leading zeros and surrounding spaces" do
    expect([ "42", "-7", "+3", "007", " 12 ", "1_000" ].map { |value| caster.call(value) }).to eq([ 42, -7, 3, 7, 12, 1000 ])
  end

  it "keeps integers, big ones included" do
    expect([ caster.call(5), caster.call(2**70) ]).to eq([ 5, 2**70 ])
  end

  it "raises ArgumentError for decimals, exponents, hex, octal prefixes and text" do
    [ "1.5", "1e3", "0x1A", "0b11", "abc", "1 2", "1,000" ].each do |value|
      expect { caster.call(value) }.to raise_error(ArgumentError)
    end
  end

  it "raises for a float value instead of truncating it" do
    expect { caster.call(1.5) }.to raise_error(ArgumentError)
  end

  it "names the type" do
    expect(caster.type_name).to eq("an integer")
  end

  describe "with a thousands separator" do
    subject(:caster) { build_caster(type: :integer, thousands_separator: ".") }

    it "accepts groups of three digits, and digits without separator" do
      expect([ "1.234", "1.234.567", "-12.345", "1234", "7" ].map { |value| caster.call(value) }).to eq([ 1234, 1_234_567, -12_345, 1234, 7 ])
    end

    it "rejects misplaced separators instead of misreading them" do
      [ "1.5", "1.23", "12.3456", ".123", "1..234", "1,5" ].each do |value|
        expect { caster.call(value) }.to raise_error(ArgumentError)
      end
    end
  end
end
