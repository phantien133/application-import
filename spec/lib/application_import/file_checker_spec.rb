RSpec.describe ApplicationImport::FileValidator do
  it "exposes the definition" do
    definition = instance_double(ApplicationImport::Definition)

    expect(described_class.new(definition).definition).to eq(definition)
  end
end
