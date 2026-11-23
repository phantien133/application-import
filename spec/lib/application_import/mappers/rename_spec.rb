RSpec.describe ApplicationImport::Mappers::Rename do
  let(:definition) { ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil } }) }

  def rename(attributes, **options)
    described_class.new(definition, options).call(attributes, nil)
  end

  it "renames the listed keys and keeps the others" do
    expect(rename({ :email => "a", :name => "Ann", "Phone" => "1" }, attributes: { email: :user_email }))
      .to eq(:name => "Ann", "Phone" => "1", :user_email => "a")
  end

  it "keeps only the renamed keys with only" do
    expect(rename({ email: "a", name: "Ann" }, attributes: { email: :user_email }, only: true)).to eq(user_email: "a")
  end

  it "skips keys missing from the attributes, nil values kept" do
    expect(rename({ email: nil }, attributes: { email: :user_email, age: :years })).to eq(user_email: nil)
  end

  it "can swap keys" do
    expect(rename({ a: 1, b: 2 }, attributes: { a: :b, b: :a })).to eq(b: 1, a: 2)
  end

  it "renames a kept unknown header (String key) when listed" do
    expect(rename({ :email => "a", "Phone" => "1" }, attributes: { Phone: :phone })).to eq(email: "a", phone: "1")
  end

  it "prefers the Symbol key when both exist" do
    expect(rename({ :email => "a", "email" => "b" }, attributes: { email: :user_email })).to eq("email" => "b", :user_email => "a")
  end

  it "keeps String keys of kept unknown headers unless listed" do
    expect(rename({ :email => "a", "Phone" => "1" }, attributes: { email: :user_email }))
      .to eq("Phone" => "1", :user_email => "a")
  end

  it "can rename into a key that already exists, overwriting it" do
    expect(rename({ email: "a", user_email: "old" }, attributes: { email: :user_email })).to eq(user_email: "a")
  end

  it "returns an empty Hash with only when nothing listed is present" do
    expect(rename({ name: "Ann" }, attributes: { email: :user_email }, only: true)).to eq({})
  end

  it "does not mutate the given attributes" do
    attributes = { email: "a" }
    rename(attributes, attributes: { email: :user_email })

    expect(attributes).to eq(email: "a")
  end
end
