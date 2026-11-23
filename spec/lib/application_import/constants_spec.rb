RSpec.describe ApplicationImport::Constants do
  it "freezes every collection constant" do
    collections = described_class.constants.map { |name| described_class.const_get(name) }.grep(Enumerable)

    expect(collections).to all(be_frozen)
  end

  it "is shared by the classes that include it" do
    expect([ ApplicationImport::Runner::HALT, ApplicationImport::Result::FAILED ]).to eq([ :application_import_halt, :failed ])
  end
end
