RSpec.describe ApplicationImport::Writers::Save do
  before { create_writer_table }

  let(:result) { ApplicationImport::Result.new }

  def write(rows, action: :skip, **output)
    callback, failures = on_failure(action)
    writer = described_class.new(writer_definition("mode" => "save", **output), result:, on_failure: callback)
    [ writer.call(rows), failures, writer ]
  end

  it "saves each record and returns the count" do
    written, failures = write(writer_rows([ "a@x.io", "Ann" ], [ "b@x.io", "Bob" ]))

    expect([ written, failures, WriterSpecUser.order(:email).pluck(:email) ]).to eq([ 2, [], %w[ a@x.io b@x.io ] ])
  end

  it "marks a record failing validation as not_saved and goes on with skip" do
    rows = writer_rows([ "a@x.io", "Ann" ], [ "b@x.io", nil ], [ "c@x.io", "Cy" ])

    written, failures = write(rows)

    expect([ written, failures, WriterSpecUser.count ]).to eq([ 2, [ 3 ], 2 ])
    expect(rows[1].errors.map { |e| [ e.code, e.message, e.details ] })
      .to eq([ [ :not_saved, "Name can't be blank", { errors: { name: [ { error: :blank } ] } } ] ])
  end

  it "marks a database error as not_saved, in a savepoint so the others still save" do
    WriterSpecUser.create!(email: "a@x.io", name: "Old")
    rows = writer_rows([ "a@x.io", "Ann" ], [ "b@x.io", "Bob" ])

    written, failures = write(rows)

    expect([ written, failures, WriterSpecUser.count ]).to eq([ 1, [ 2 ], 2 ])
    expect(rows.first.errors.first.details).to eq(exception: "ActiveRecord::RecordNotUnique")
  end

  it "hands output.save to record.save as-is" do
    written, = write(writer_rows([ "b@x.io", nil ]), "save" => { "validate" => false })

    expect([ written, WriterSpecUser.where(name: nil).count ]).to eq([ 1, 1 ])
  end

  describe "abort" do
    let(:rows) { writer_rows([ "a@x.io", "Ann" ], [ "b@x.io", nil ], [ "c@x.io", "Cy" ]) }

    it "stops at the failing row and rolls everything back in the transaction (default)" do
      written, failures, writer = write(rows, action: :abort)

      expect([ written, failures, writer.aborted?, WriterSpecUser.count ]).to eq([ 0, [ 3 ], true, 0 ])
    end

    it "keeps the rows saved before it without transaction" do
      written, failures, writer = write(rows, :action => :abort, "transaction" => false)

      expect([ written, failures, writer.aborted?, WriterSpecUser.pluck(:email) ]).to eq([ 1, [ 3 ], true, [ "a@x.io" ] ])
    end
  end

  it "raises ConfigError for a row without record" do
    row = ApplicationImport::Row.new(line: 2, attributes: {}, raw: [])

    expect { write([ row ]) }.to raise_error(ApplicationImport::Errors::ConfigError, "users: row 2 has no record to write")
  end
end
