RSpec.describe ApplicationImport::Transformers::Default do
  it "sets the value when the attribute is blank or missing" do
    expect([ transform({ role: nil }, attribute: :role, value: "member").first, transform({ role: " " }, attribute: :role, value: "member").first,
      transform({}, attribute: :role, value: "member").first ]).to all(eq(role: "member"))
  end

  it "keeps a present value, false and 0 included" do
    expect([ transform({ role: "admin" }, attribute: :role, value: "member").first,
      transform({ count: 0 }, attribute: :count, value: 1).first ]).to eq([ nil, nil ])
  end

  it "replaces false, which Rails treats as blank" do
    expect(transform({ active: false }, attribute: :active, value: true).first).to eq(active: true)
  end

  it "can set nil or false as the default" do
    expect([ transform({ role: "" }, attribute: :role, value: nil).first, transform({}, attribute: :active, value: false).first ])
      .to eq([ { role: nil }, { active: false } ])
  end

  it "treats empty arrays and hashes as blank" do
    expect([ transform({ tags: [] }, attribute: :tags, value: [ "x" ]).first, transform({ meta: {} }, attribute: :meta, value: { a: 1 }).first ])
      .to eq([ { tags: [ "x" ] }, { meta: { a: 1 } } ])
  end
end
