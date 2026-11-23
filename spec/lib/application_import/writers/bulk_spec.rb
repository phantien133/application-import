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

  it "hands output.import to Model.import with the upsert options" do
    allow(WriterSpecUser).to receive(:import).and_call_original

    write(writer_rows([ "a@x.io", nil ]), "upsert" => { "conflict_target" => [ "email" ], "update" => [ "name" ] },
      "import" => { "validate" => false })

    expect(WriterSpecUser).to have_received(:import)
      .with(anything, on_duplicate_key_update: { conflict_target: [ :email ], columns: [ :name ] }, validate: false)
    expect(WriterSpecUser.where(name: nil).count).to eq(1)
  end

  it "counts only inserted rows with on_duplicate_key_ignore" do
    WriterSpecUser.create!(email: "a@x.io", name: "Old")

    written, failures = write(writer_rows([ "a@x.io", "Ann" ], [ "b@x.io", "Bob" ]), "import" => { "on_duplicate_key_ignore" => true })

    expect([ written, failures, WriterSpecUser.order(:email).pluck(:name) ]).to eq([ 1, [], %w[ Old Bob ] ])
  end

  it "counts upserted rows as written" do
    WriterSpecUser.create!(email: "a@x.io", name: "Old")

    written, = write(writer_rows([ "a@x.io", "New" ], [ "b@x.io", "Bob" ]),
      "upsert" => { "conflict_target" => [ "email" ], "update" => [ "name" ] })

    expect([ written, WriterSpecUser.order(:email).pluck(:name) ]).to eq([ 2, %w[ New Bob ] ])
  end

  it "marks every row of a batch not_saved with all_or_none when one is invalid" do
    rows = writer_rows([ "a@x.io", "Ann" ], [ "b@x.io", nil ], [ "c@x.io", "Cy" ])

    written, failures = write(rows, "import" => { "all_or_none" => true })

    expect([ written, failures.sort, WriterSpecUser.count ]).to eq([ 0, [ 2, 3, 4 ], 0 ])
    expect(rows.first.errors.map(&:details)).to eq([ { all_or_none: true } ])
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
