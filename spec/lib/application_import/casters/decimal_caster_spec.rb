RSpec.describe ApplicationImport::Casters::DecimalCaster do
  subject(:caster) { build_caster(type: :decimal) }

  it "parses numbers as BigDecimal" do
    values = [ "1.50", " -2 ", "1e2", "0.1", "3" ].map { |value| caster.call(value) }

    expect(values).to eq([ BigDecimal("1.5"), BigDecimal(-2), BigDecimal(100), BigDecimal("0.1"), BigDecimal(3) ])
    expect(values).to all(be_a(BigDecimal))
  end

  it "keeps BigDecimal values and converts floats through their string form" do
    expect([ caster.call(BigDecimal("2.5")), caster.call(0.1), caster.call(7) ]).to eq([ BigDecimal("2.5"), BigDecimal("0.1"), BigDecimal(7) ])
  end

  it "raises ArgumentError for text and locale formats" do
    [ "abc", "1.2.3", "1,5", "1 000" ].each do |value|
      expect { caster.call(value) }.to raise_error(ArgumentError)
    end
  end

  it "names the type" do
    expect(caster.type_name).to eq("a number")
  end
end
