RSpec.describe ApplicationImport::Transformers::Base do
  let(:definition) { ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil } }) }

  it "exposes definition, options, context and logger with defaults" do
    transformer = described_class.new(definition)

    expect([ transformer.definition, transformer.options, transformer.context, transformer.logger ])
      .to eq([ definition, {}, {}, ApplicationImport.logger ])
  end

  it "takes options, the run's context and logger" do
    logger = ActiveSupport::Logger.new(nil)
    transformer = described_class.new(definition, { a: 1 }, context: { user_id: 1 }, logger:)

    expect([ transformer.options, transformer.context, transformer.logger ]).to eq([ { a: 1 }, { user_id: 1 }, logger ])
  end

  it "requires subclasses to implement call" do
    expect { described_class.new(definition).call({}, nil) }
      .to raise_error(NotImplementedError, "ApplicationImport::Transformers::Base#call")
  end

  %w[ Concat Default Map Normalize Context ].each do |name|
    it "is the base of #{name}" do
      expect(ApplicationImport::Transformers.const_get(name).superclass).to eq(described_class)
    end
  end
end
