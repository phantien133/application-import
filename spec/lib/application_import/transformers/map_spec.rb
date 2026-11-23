RSpec.describe ApplicationImport::Transformers::Map do
  let(:values) { { "Quản trị" => "admin", "Thành viên" => "member" } }

  it "replaces values through the table, ignoring case and surrounding spaces by default" do
    expect([ transform({ role: "Quản trị" }, attribute: :role, values:).first, transform({ role: " QUẢN TRỊ " }, attribute: :role, values:).first ])
      .to all(eq(role: "admin"))
  end

  it "compares exactly with case_sensitive" do
    expect(transform({ role: "quản trị" }, attribute: :role, values:, case_sensitive: true).first).to be_nil
  end

  it "writes to another attribute with to" do
    expect(transform({ role: "Thành viên" }, attribute: :role, values:, to: :role_code).first).to eq(role_code: "member")
  end

  it "leaves unknown values alone by default" do
    result, row = transform({ role: "guest" }, attribute: :role, values:)

    expect([ result, row.errors ]).to eq([ nil, [] ])
  end

  it "adds not_mapped for unknown values with strict" do
    result, row = transform({ role: "guest" }, attribute: :role, values:, strict: true)

    expect(result).to be_nil
    expect(row.errors.map { |e| [ e.code, e.column, e.message ] })
      .to eq([ [ :not_mapped, "role", 'role "guest" is not one of: Quản trị, Thành viên' ] ])
  end

  it "leaves blank values alone, even with strict" do
    result, row = transform({ role: nil }, attribute: :role, values:, strict: true)

    expect([ result, row.errors ]).to eq([ nil, [] ])
  end

  it "maps non-string values by their string form" do
    expect(transform({ level: 1 }, attribute: :level, values: { "1" => "low" }).first).to eq(level: "low")
  end

  it "maps to non-string values" do
    expect(transform({ active: "Có" }, attribute: :active, values: { "Có" => true, "Không" => false }).first).to eq(active: true)
  end

  it "keeps the source attribute when writing to another one" do
    result, = transform({ role: "Thành viên" }, attribute: :role, values:, to: :role_code)

    expect(result.keys).to eq([ :role_code ])
  end

  it "builds the table once per instance" do
    mapper = described_class.new(transformer_definition, { attribute: :role, values: })
    allow(mapper).to receive(:normalize).and_call_original
    row = ApplicationImport::Row.new(line: 2, attributes: {}, raw: [])

    3.times { mapper.call({ role: "Quản trị" }, row) }

    expect(mapper).to have_received(:normalize).exactly(values.size + 3).times
  end

  it "ignores a missing attribute" do
    expect(transform({}, attribute: :role, values:, strict: true).first).to be_nil
  end
end
