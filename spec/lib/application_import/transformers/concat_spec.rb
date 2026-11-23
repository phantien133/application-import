RSpec.describe ApplicationImport::Transformers::Concat do
  it "joins the attributes with a space by default" do
    expect(transform({ first: "Ann", last: "Lee" }, from: %i[ first last ], to: :full_name).first).to eq(full_name: "Ann Lee")
  end

  it "uses the separator, skips blank values and stringifies others" do
    expect(transform({ a: "x", b: nil, c: " ", d: 7 }, from: %i[ a b c d ], to: :code, separator: "-").first).to eq(code: "x-7")
  end

  it "gives nil when every value is blank" do
    expect(transform({ a: nil, b: "" }, from: %i[ a b ], to: :code).first).to eq(code: nil)
  end

  it "treats missing keys as blank" do
    expect(transform({ a: "x" }, from: %i[ a missing ], to: :code).first).to eq(code: "x")
  end

  it "works with a single source and an empty separator" do
    expect([ transform({ a: "x" }, from: %i[ a ], to: :b).first, transform({ a: "x", b: "y" }, from: %i[ a b ], to: :c, separator: "").first ])
      .to eq([ { b: "x" }, { c: "xy" } ])
  end

  it "can overwrite one of its sources" do
    expect(transform({ name: "Ann", last: "Lee" }, from: %i[ name last ], to: :name).first).to eq(name: "Ann Lee")
  end

  it "adds no row error" do
    _, row = transform({ a: nil }, from: %i[ a ], to: :b)

    expect(row.errors).to eq([])
  end
end
