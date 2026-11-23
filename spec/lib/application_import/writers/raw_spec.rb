RSpec.describe ApplicationImport::Writers::Raw do
  before { create_writer_table }

  let(:result) { ApplicationImport::Result.new }

  it "adds the rows' attributes to the result without touching the database" do
    callback, failures = on_failure
    rows = writer_rows([ "a@x.io", "Ann" ], [ "b@x.io", nil ])

    written = described_class.new(writer_definition("mode" => "raw"), result:, on_failure: callback).call(rows)

    expect([ written, result.records, WriterSpecUser.count, failures ])
      .to eq([ 2, [ { email: "a@x.io", name: "Ann" }, { email: "b@x.io", name: nil } ], 0, [] ])
  end

  it "works without output.model and opens no transaction" do
    definition = ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil } })
    row = ApplicationImport::Row.new(line: 2, attributes: { email: "a" }, raw: [ "a" ])

    expect(described_class.new(definition, result:, on_failure: ->(_row) { }).call([ row ])).to eq(1)
  end
end
