RSpec.describe ApplicationImport::Column do
  let(:column) do
    described_class.new(key: :email, headers: [ "Email", "E-mail" ], type: :string, options: { required: true })
  end

  it "uses the first header as the canonical header" do
    expect(column.header).to eq("Email")
  end

  it "is required only when options[:required] is true" do
    expect([ column.required?, column.with(options: {}).required?, column.with(options: { required: "yes" }).required? ])
      .to eq([ true, false, false ])
  end

  it "is an immutable value object" do
    expect(column).to be_frozen
    expect(column).to eq(described_class.new(**column.to_h))
  end
end
