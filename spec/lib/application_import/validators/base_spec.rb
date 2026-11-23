RSpec.describe ApplicationImport::Validators::Base do
  let(:definition) { instance_double(ApplicationImport::Definition) }

  it "exposes the definition and options" do
    validator = described_class.new(definition, { keys: [ :email ] })

    expect([ validator.definition, validator.options ]).to eq([ definition, { keys: [ :email ] } ])
  end

  it "defaults options and context to empty hashes and the logger to ApplicationImport.logger" do
    validator = described_class.new(definition)

    expect([ validator.options, validator.context, validator.logger ]).to eq([ {}, {}, ApplicationImport.logger ])
  end

  it "takes the run's context and logger" do
    logger = ActiveSupport::Logger.new(nil)
    validator = described_class.new(definition, {}, context: { user_id: 1 }, logger:)

    expect([ validator.context, validator.logger ]).to eq([ { user_id: 1 }, logger ])
  end

  it "requires subclasses to implement call" do
    expect { described_class.new(definition).call }.to raise_error(NotImplementedError, "ApplicationImport::Validators::Base#call")
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
