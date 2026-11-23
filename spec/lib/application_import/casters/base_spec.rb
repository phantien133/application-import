RSpec.describe ApplicationImport::Casters::Base do
  let(:definition) { ApplicationImport::Definition.new(:users, { "columns" => { "phone" => { "header" => "Phone" } } }) }
  let(:caster) { described_class.new(definition.columns.first, definition:) }

  it "exposes the column, definition and logger" do
    expect([ caster.column.key, caster.definition, caster.logger ]).to eq([ :phone, definition, ApplicationImport.logger ])
  end

  it "requires subclasses to implement call" do
    expect { caster.call("x") }.to raise_error(NotImplementedError, "ApplicationImport::Casters::Base#call")
  end

  it "raises Caster::Invalid naming the column, or with a given message" do
    expect { caster.invalid! }.to raise_error(ApplicationImport::Caster::Invalid, "Phone must be valid")
    expect { caster.invalid!("bad") }.to raise_error(ApplicationImport::Caster::Invalid, "bad")
  end

  %w[ StringCaster IntegerCaster DecimalCaster BooleanCaster DateCaster DatetimeCaster ].each do |name|
    it "is the base of #{name}" do
      expect(ApplicationImport::Casters.const_get(name).superclass).to eq(described_class)
    end
  end
end
