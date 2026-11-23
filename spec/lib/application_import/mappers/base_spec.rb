RSpec.describe ApplicationImport::Mappers::Base do
  let(:definition) { ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil } }) }

  it "exposes definition, options, context and logger with defaults" do
    mapper = described_class.new(definition)

    expect([ mapper.definition, mapper.options, mapper.context, mapper.logger ]).to eq([ definition, {}, {}, ApplicationImport.logger ])
  end

  it "requires subclasses to implement call" do
    expect { described_class.new(definition).call({}, nil) }.to raise_error(NotImplementedError, "ApplicationImport::Mappers::Base#call")
  end

  it "is the base of Rename" do
    expect(ApplicationImport::Mappers::Rename.superclass).to eq(described_class)
  end

  it "takes options, the run's context and logger" do
    logger = ActiveSupport::Logger.new(nil)
    mapper = described_class.new(definition, { a: 1 }, context: { user_id: 1 }, logger:)

    expect([ mapper.options, mapper.context, mapper.logger ]).to eq([ { a: 1 }, { user_id: 1 }, logger ])
  end
end
