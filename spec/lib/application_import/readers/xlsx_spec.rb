RSpec.describe ApplicationImport::Readers::Xlsx do
  let(:definition) { ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil }, "file" => { "format" => "xlsx" } }) }
  let(:reader) { described_class.new(definition, ApplicationImport::Source.new(filename: "u.xlsx", io: StringIO.new(""))) }

  it "is a Base reader" do
    expect(described_class.superclass).to eq(ApplicationImport::Readers::Base)
  end

  it "raises NotImplementedError when read" do
    expect { reader.to_a }.to raise_error(NotImplementedError, "ApplicationImport::Readers::Xlsx: XLSX reading is not implemented yet")
  end

  it "is picked by file.format xlsx" do
    expect(definition.reader_class).to eq(described_class)
  end

  it "keeps the shared reader behaviour from Base" do
    expect([ reader.headers?, reader.each ]).to match([ true, an_instance_of(Enumerator) ])
  end
end
