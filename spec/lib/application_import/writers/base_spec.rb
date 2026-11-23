RSpec.describe ApplicationImport::Writers::Base do
  before { create_writer_table }

  let(:result) { ApplicationImport::Result.new }

  it "requires subclasses to implement write" do
    callback, = on_failure
    writer = described_class.new(writer_definition, result:, on_failure: callback)

    expect { writer.call(writer_rows([ "a@x.io", "Ann" ])) }.to raise_error(NotImplementedError, "ApplicationImport::Writers::Base#write")
  end

  it "writes nothing and opens no transaction for no rows" do
    callback, = on_failure
    allow(WriterSpecUser).to receive(:transaction)

    expect(described_class.new(writer_definition, result:, on_failure: callback).call([])).to eq(0)
    expect(WriterSpecUser).not_to have_received(:transaction)
  end

  it "starts not aborted" do
    callback, = on_failure

    expect(described_class.new(writer_definition, result:, on_failure: callback)).not_to be_aborted
  end
end
