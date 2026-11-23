RSpec.describe ApplicationImport::Transformers::Normalize do
  it "applies the operations in order to each String attribute" do
    expect(transform({ email: "  A@X.IO ", name: " ann   lee " }, attributes: %i[ email name ], with: %w[ strip downcase ]).first)
      .to eq(email: "a@x.io", name: "ann   lee")
  end

  it "supports squish and upcase" do
    expect(transform({ code: "  ab   cd " }, attributes: %i[ code ], with: %w[ squish upcase ]).first).to eq(code: "AB CD")
  end

  it "leaves non-String and missing values alone" do
    expect(transform({ age: 3, name: nil }, attributes: %i[ age name missing ], with: %w[ strip ]).first).to eq({})
  end

  it "applies each operation" do
    attributes = { value: "  Ann   LEE  " }

    expect(%w[ strip downcase upcase squish ].map { |operation| transform(attributes, attributes: %i[ value ], with: [ operation ]).first[:value] })
      .to eq([ "Ann   LEE", "  ann   lee  ", "  ANN   LEE  ", "Ann LEE" ])
  end

  it "handles multibyte strings" do
    expect(transform({ name: " TRẦN  ĐỨC " }, attributes: %i[ name ], with: %w[ squish downcase ]).first).to eq(name: "trần đức")
  end

  it "does not mutate the original value" do
    value = +" Ann "
    transform({ name: value }, attributes: %i[ name ], with: %w[ strip ])

    expect(value).to eq(" Ann ")
  end
end
