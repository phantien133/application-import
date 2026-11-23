RSpec.describe ApplicationImport::RecordBuilder do
  before do
    ActiveRecord::Base.connection.create_table(:record_builder_spec_users, temporary: true) do |t|
      t.string :email
      t.string :full_name
      t.string :phone
      t.boolean :admin, default: false
    end
    stub_const("RbUser", Class.new(ApplicationRecord) { self.table_name = "record_builder_spec_users" })
  end

  let(:columns) { [ ApplicationImport::Column.new(key: :email, headers: [ "Email" ], type: :string, options: {}) ] }

  def build(attributes, assign_unknown: false)
    described_class.build(RbUser, attributes, columns, assign_unknown:)
  end

  it "assigns declared columns only by default" do
    record = build({ :email => "a@x.io", "Phone" => "123", "admin" => "true" })

    expect([ record.email, record.phone, record.admin ]).to eq([ "a@x.io", nil, false ])
  end

  it "assigns generated keys the model can set, ignoring the others" do
    record = described_class.build(RbUser, { email: "a@x.io", full_name: "Ann", nope: 1 }, columns, generated: %i[ full_name nope ])

    expect([ record.email, record.full_name ]).to eq([ "a@x.io", "Ann" ])
  end

  context "with assign_unknown" do
    it "assigns kept headers naming a model attribute, as read" do
      record = build({ :email => "a@x.io", "Phone" => " 090 ", "Full Name" => "Ann" }, assign_unknown: true)

      expect([ record.email, record.phone, record.full_name ]).to eq([ "a@x.io", " 090 ", "Ann" ])
    end

    it "ignores headers that are not attributes, the primary key and declared columns" do
      record = build({ :email => "a@x.io", "nickname" => "x", "ID" => "99", "Email" => "other@x.io" }, assign_unknown: true)

      expect([ record.id, record.email, record.respond_to?(:nickname) ]).to eq([ nil, "a@x.io", false ])
    end

    it "lets the model type-cast the raw value" do
      expect(build({ "admin" => "1" }, assign_unknown: true).admin).to be(true)
    end
  end

  describe ".attribute_for" do
    it "matches headers to attributes, downcased with spaces as underscores" do
      expect([ "full name", " FULL   NAME ", "Phone", "id", "nope" ].map { |header| described_class.attribute_for(RbUser, header) })
        .to eq([ "full_name", "full_name", "phone", nil, nil ])
    end
  end
end
