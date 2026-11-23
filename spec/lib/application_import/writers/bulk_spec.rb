RSpec.describe ApplicationImport::Writers::Bulk do
  before { create_writer_table }

  let(:result) { ApplicationImport::Result.new }

  def write(rows, action: :skip, **output)
    callback, failures = on_failure(action)
    writer = described_class.new(writer_definition(output), result:, on_failure: callback)
    [ writer.call(rows), failures, writer ]
  end

  it "imports the records with activerecord-import and returns the count" do
    allow(WriterSpecUser).to receive(:import).and_call_original

    written, failures = write(writer_rows([ "a@x.io", "Ann" ], [ "b@x.io", "Bob" ]))

    expect([ written, failures, WriterSpecUser.count ]).to eq([ 2, [], 2 ])
    expect(WriterSpecUser).to have_received(:import).once
  end

  it "imports per batch_size" do
    allow(WriterSpecUser).to receive(:import).and_call_original

    written, = write(writer_rows([ "a", "A" ], [ "b", "B" ], [ "c", "C" ]), "batch_size" => 2)

    expect([ written, WriterSpecUser.count ]).to eq([ 3, 3 ])
    expect(WriterSpecUser).to have_received(:import).twice
  end

  it "maps failed_instances back to their rows as not_saved" do
    rows = writer_rows([ "a@x.io", "Ann" ], [ "b@x.io", nil ], [ "c@x.io", "Cy" ])

    written, failures = write(rows)

    expect([ written, failures, WriterSpecUser.count ]).to eq([ 2, [ 3 ], 2 ])
    expect(rows[1].errors.map { |e| [ e.code, e.message ] }).to eq([ [ :not_saved, "Name can't be blank" ] ])
  end

  it "marks every row of a batch hitting a database error, in a savepoint so other batches still import" do
    WriterSpecUser.create!(email: "a@x.io", name: "Old")
    rows = writer_rows([ "a@x.io", "Ann" ], [ "b@x.io", "Bob" ], [ "c@x.io", "Cy" ])

    written, failures = write(rows, "batch_size" => 2, "import" => { "validate" => false })

    expect([ written, failures, WriterSpecUser.order(:email).pluck(:email) ]).to eq([ 1, [ 2, 3 ], %w[ a@x.io c@x.io ] ])
    expect(rows.first.errors.first.details).to eq(exception: "ActiveRecord::RecordNotUnique")
  end

  it "upserts with output.upsert" do
    WriterSpecUser.create!(email: "a@x.io", name: "Old")

    written, = write(writer_rows([ "a@x.io", "New" ]), "upsert" => { "conflict_target" => [ "email" ], "update" => [ "name" ] })

    expect([ written, WriterSpecUser.pluck(:name) ]).to eq([ 1, [ "New" ] ])
  end

  it "hands output.import to Model.import as-is, on top of the upsert options" do
    allow(WriterSpecUser).to receive(:import).and_call_original

    write(writer_rows([ "a@x.io", nil ]), "upsert" => { "conflict_target" => [ "email" ], "update" => [ "name" ] },
      "import" => { "validate" => false, "on_duplicate_key_update" => { "conflict_target" => [ "email" ], "columns" => [] } })

    expect(WriterSpecUser).to have_received(:import)
      .with(anything, validate: false, on_duplicate_key_update: { conflict_target: [ "email" ], columns: [] })
    expect(WriterSpecUser.where(name: nil).count).to eq(1)
  end

  describe "abort" do
    let(:rows) { writer_rows([ "a", "A" ], [ "b", "B" ], [ "c", nil ], [ "d", "D" ]) }

    it "stops after the failing batch and rolls everything back (default transaction)" do
      written, failures, writer = write(rows, :action => :abort, "batch_size" => 2)

      expect([ written, failures, writer.aborted?, WriterSpecUser.count ]).to eq([ 0, [ 4 ], true, 0 ])
    end

    it "keeps earlier batches and the batch's valid rows without transaction" do
      written, failures, = write(rows, :action => :abort, "batch_size" => 2, "transaction" => false)

      expect([ written, failures, WriterSpecUser.order(:email).pluck(:email) ]).to eq([ 3, [ 4 ], %w[ a b d ] ])
    end
  end
end
