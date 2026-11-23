RSpec.describe ApplicationImport::Transformers::Context do
  it "copies a context value to an attribute, Symbol or String keys" do
    expect([ transform({}, context: { user_id: 7 }, key: :user_id, to: :created_by_id).first,
      transform({}, context: { "user_id" => 7 }, key: :user_id, to: :created_by_id).first ])
      .to all(eq(created_by_id: 7))
  end

  it "gives nil for a missing key" do
    expect(transform({}, key: :user_id, to: :created_by_id).first).to eq(created_by_id: nil)
  end

  it "prefers the Symbol key and keeps falsy values" do
    expect([ transform({}, context: { :flag => false, "flag" => true }, key: :flag, to: :x).first,
      transform({}, context: { "tenant" => nil }, key: :tenant, to: :tenant_id).first ])
      .to eq([ { x: false }, { tenant_id: nil } ])
  end

  it "copies nested values as they are" do
    expect(transform({}, context: { tags: %w[ a b ] }, key: :tags, to: :tags).first).to eq(tags: %w[ a b ])
  end
end
