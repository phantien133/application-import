RSpec.describe ApplicationImport::Validators::Base do
  let(:definition) { instance_double(ApplicationImport::Definition) }

  it "exposes the definition and options" do
    validator = described_class.new(definition, { keys: [ :email ] })

    expect([ validator.definition, validator.options ]).to eq([ definition, { keys: [ :email ] } ])
  end

  it "defaults options to an empty hash" do
    expect(described_class.new(definition).options).to eq({})
  end

  {
    ApplicationImport::Validators::FileValidator => described_class,
    ApplicationImport::Validators::RowValidator => described_class,
    ApplicationImport::Validators::RowsValidator => described_class,
    ApplicationImport::Validators::VerifyValidator => described_class,
    ApplicationImport::Validators::ModelValidator => ApplicationImport::Validators::RowValidator,
    ApplicationImport::Validators::UniqueInFile => ApplicationImport::Validators::RowsValidator
  }.each do |klass, parent|
    it "#{klass.name.demodulize} inherits #{parent.name.demodulize}" do
      expect(klass.superclass).to eq(parent)
    end
  end
end
