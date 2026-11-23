RSpec.describe ApplicationImport::Handler do
  subject(:handler) { described_class.new(definition, context) }

  let(:context) { { user_id: 1 } }
  let(:result) { ApplicationImport::Result.new }
  let(:definition) { build_definition }

  def build_definition(output: {})
    ApplicationImport::Definition.new(:users, {
      "columns" => { "email" => nil, "name" => nil, "nickname" => nil }, "output" => output
    })
  end

  def row(attributes = {})
    ApplicationImport::Row.new(line: 2, attributes:, raw: attributes.values)
  end

  it "exposes the definition and context" do
    expect([ handler.definition, handler.context ]).to eq([ definition, context ])
  end

  it "defaults context to an empty hash" do
    expect(described_class.new(definition).context).to eq({})
  end

  describe "#map_row" do
    it "keeps the attributes" do
      attributes = { email: "a@example.com" }

      expect(handler.map_row(attributes, row(attributes))).to equal(attributes)
    end
  end

  describe "#build_record" do
    it "returns nil without output.model" do
      expect(handler.build_record({ email: "a@example.com" }, row)).to be_nil
    end

    context "with output.model" do
      let(:definition) { build_definition(output: { "model" => "HandlerSpecUser" }) }

      before do
        ActiveRecord::Base.connection.create_table(:handler_spec_users, temporary: true) do |t|
          t.string :email
          t.string :name
          t.boolean :admin, default: false
        end
        stub_const("HandlerSpecUser", Class.new(ApplicationRecord) { self.table_name = "handler_spec_users" })
      end

      it "builds a new record with the declared columns the model can set" do
        record = handler.build_record({ email: "a@example.com", name: "Ann", nickname: "an" }, row)

        expect([ record.class, record.new_record?, record.email, record.name ])
          .to eq([ HandlerSpecUser, true, "a@example.com", "Ann" ])
      end

      it "skips declared columns the model has no setter for" do
        expect { handler.build_record({ nickname: "an" }, row) }.not_to raise_error
      end

      it "never assigns kept unknown headers" do
        record = handler.build_record({ :email => "a@example.com", "admin" => "true", :admin => true }, row)

        expect(record.admin).to be(false)
      end

      it "leaves attributes missing from the row unset" do
        expect(handler.build_record({ email: "a@example.com" }, row).name).to be_nil
      end

      it "uses a custom setter defined on the model" do
        HandlerSpecUser.define_method(:nickname=) { |value| self.name = "~#{value}" }

        expect(handler.build_record({ nickname: "an" }, row).name).to eq("~an")
      end
    end
  end

  describe "#write" do
    it "delegates to the writer and returns its count" do
      rows = [ row(email: "a"), row(email: "b") ]
      writer = instance_spy(Proc, call: 2)

      expect(handler.write(rows, writer)).to eq(2)
      expect(writer).to have_received(:call).with(rows)
    end
  end

  it "has no-op validation hooks that add no errors" do
    rows = [ row(email: "a") ]

    handler.validate_file(Object.new, result)
    handler.validate_row(rows.first, result)
    handler.validate_rows(rows.first, result, {})
    handler.verify(rows, result)
    handler.after_import(result)

    expect([ result.errors, rows.first.errors ]).to eq([ [], [] ])
  end

  it "no longer has transform: writers work on rows" do
    expect(handler).not_to respond_to(:transform)
  end
end
