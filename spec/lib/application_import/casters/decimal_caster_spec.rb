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

  it "reports NaN and Infinity as invalid (they pass every min / max)" do
    [ "NaN", "Infinity", "-Infinity", BigDecimal("NaN"), Float::INFINITY ].each do |value|
      expect { caster.call(value) }.to raise_error(ApplicationImport::Caster::Invalid, "Value must be a number")
    end
  end

  describe "with separators" do
    subject(:caster) { build_caster(type: :decimal, decimal_separator: ",", thousands_separator: ".") }

    it "parses the configured format" do
      expect([ "1.234,5", "1,25", "-0,5", "1234", "1.234.567,891" ].map { |value| caster.call(value) })
        .to eq([ BigDecimal("1234.5"), BigDecimal("1.25"), BigDecimal("-0.5"), BigDecimal(1234), BigDecimal("1234567.891") ])
    end

    it "rejects other formats" do
      [ "1,234.5", "1.5", "1e3", "1,2,3", "12.34,5" ].each do |value|
        expect { caster.call(value) }.to raise_error(ArgumentError)
      end
    end

    it "accepts a space as thousands separator" do
      caster = build_caster(type: :decimal, decimal_separator: ",", thousands_separator: " ")

      expect(caster.call("1 234 567,5")).to eq(BigDecimal("1234567.5"))
    end

    it "uses file.numbers unless the column has its own" do
      definition = ApplicationImport::Definition.new(:users, {
        "columns" => { "email" => nil }, "file" => { "numbers" => { "decimal_separator" => "," } }
      })
      plain = ApplicationImport::Column.new(key: :value, headers: [ "Value" ], type: :decimal, options: {})
      own = ApplicationImport::Column.new(key: :value, headers: [ "Value" ], type: :decimal, options: { decimal_separator: "." })

      expect([ described_class.new(plain, definition:).call("1,5"), described_class.new(own, definition:).call("1.5") ])
        .to eq([ BigDecimal("1.5"), BigDecimal("1.5") ])
    end
  end
end
