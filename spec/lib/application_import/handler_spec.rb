RSpec.describe ApplicationImport::Handler do
  subject(:handler) { described_class.new(definition, context) }

  let(:definition) { instance_double(ApplicationImport::Definition) }
  let(:context) { { user_id: 1 } }
  let(:errors) { [] }

  it "exposes the definition and context" do
    expect([ handler.definition, handler.context ]).to eq([ definition, context ])
  end

  it "defaults context to an empty hash" do
    expect(described_class.new(definition).context).to eq({})
  end

  it "keeps the mapped attributes in map_row" do
    attributes = { email: "a@example.com" }

    expect(handler.map_row(attributes, [ "a@example.com" ])).to equal(attributes)
  end

  it "builds records from row attributes in transform" do
    rows = [ double(attributes: { id: 1 }), double(attributes: { id: 2 }) ]

    expect(handler.transform(rows)).to eq([ { id: 1 }, { id: 2 } ])
  end

  it "delegates write to the writer and returns its count" do
    writer = instance_spy(Proc, call: 2)

    expect(handler.write([ { id: 1 }, { id: 2 } ], writer)).to eq(2)
    expect(writer).to have_received(:call).with([ { id: 1 }, { id: 2 } ])
  end

  it "has no-op validation hooks that add no errors" do
    handler.validate_file_meta(double, errors)
    handler.validate_row(double)
    handler.validate_file([], errors)
    handler.verify([], errors)
    handler.after_import(double)

    expect(errors).to be_empty
  end
end
