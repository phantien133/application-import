RSpec.describe ApplicationImport::Runner::Rows do
  let(:events) { [] }

  before do
    log = events
    stub_const("RowsSpecRunner", Class.new(ApplicationImport::Runner) { define_method(:write_rows) { log << [ :write_rows, rows.map(&:line) ] } })
    stub_const("RowsSpecHandler", Class.new(ApplicationImport::Handler) do
      define_method(:map_row) { |attributes, row| (log << [ :map_row, row.line ]) && attributes.merge(mapped: true) }
      define_method(:validate_row) { |row, _result| log << [ :validate_row, row.line ] }
      define_method(:validate_rows) { |row, _result, _cache| log << [ :validate_rows, row.line ] }
      define_method(:verify) { |rows, _result| log << [ :verify, rows.map(&:line) ] }
    end)
  end

  def content
    "email\na@x.io\nb@x.io\n"
  end

  def config
    {}
  end

  def definition
    ApplicationImport::Definition.new(:users, {
      "handler" => "RowsSpecHandler", "file" => {}, "columns" => { "email" => nil }
    }.merge(config))
  end

  def run
    RowsSpecRunner.new(definition, ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new(content.b)), logger: nil).call
  end

  def validator(stage, &block)
    base = { row: ApplicationImport::Validators::RowValidator, rows: ApplicationImport::Validators::RowsValidator,
             verify: ApplicationImport::Validators::VerifyValidator }.fetch(stage)
    Class.new(base) { define_method(:call, &block) }
  end

  it "streams each row through map, row checks and rows checks, then verifies and writes the kept rows" do
    result = run

    expect(result.stats[:total]).to eq(2)
    expect(events).to eq([
      [ :map_row, 2 ], [ :validate_row, 2 ], [ :validate_rows, 2 ],
      [ :map_row, 3 ], [ :validate_row, 3 ], [ :validate_rows, 3 ],
      [ :verify, [ 2, 3 ] ], [ :write_rows, [ 2, 3 ] ]
    ])
  end

  it "runs the handler hooks alone when the row and rows stages are empty" do
    allow(self).to receive(:config).and_return("validators" => { "row" => [], "rows" => nil })

    expect(run.status).to eq(:completed)
    expect(events).to include([ :validate_row, 2 ], [ :validate_rows, 2 ], [ :write_rows, [ 2, 3 ] ])
  end

  it "keeps the mapped attributes on the row" do
    runner = RowsSpecRunner.new(definition, ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new(content)), logger: nil)
    runner.call

    expect(runner.rows.map(&:attributes)).to eq([ { email: "a@x.io", mapped: true }, { email: "b@x.io", mapped: true } ])
  end

  context "with output.model" do
    def config
      { "output" => { "model" => "RowsSpecUser" } }
    end

    before do
      ActiveRecord::Base.connection.create_table(:rows_spec_users, temporary: true) { |t| t.string :email }
      stub_const("RowsSpecUser", Class.new(ApplicationRecord) { self.table_name = "rows_spec_users" })
    end

    it "builds a record per row" do
      runner = RowsSpecRunner.new(definition, ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new(content)), logger: nil)
      runner.call

      expect(runner.rows.map { |row| [ row.record.class, row.record.email ] }).to eq([ [ RowsSpecUser, "a@x.io" ], [ RowsSpecUser, "b@x.io" ] ])
    end
  end

  describe "on_error per row" do
    before do
      stub_const("RejectB", validator(:row) { |row, _result| row.add_error(code: :bad, message: "bad b") if row.attributes[:email].start_with?("b") })
    end

    def content
      "email\na@x.io\nb@x.io\nc@x.io\n"
    end

    def config
      { "validators" => { "row" => [ { "class" => "RejectB" } ] }, "on_error" => on_error }
    end

    context "with abort (default)" do
      def on_error
        "abort"
      end

      it "records the error and halts right away" do
        result = run

        expect([ result.status, result.errors.map { |e| [ e.line, e.code ] }, result.stats.values_at(:total, :invalid) ])
          .to eq([ :failed, [ [ 3, :bad ] ], [ 2, 1 ] ])
        expect(events.map(&:first)).not_to include(:verify, :import)
      end
    end

    context "with skip" do
      def on_error
        "skip"
      end

      it "finishes the row checks, then drops the row from rows checks, verify and write_rows" do
        result = run

        expect([ result.status, result.stats[:invalid] ]).to eq([ :completed_with_errors, 1 ])
        expect(events).to include([ :verify, [ 2, 4 ] ], [ :write_rows, [ 2, 4 ] ])
        expect(events).to include([ :validate_row, 3 ])
        expect(events).not_to include([ :validate_rows, 3 ])
      end
    end

    context "with allow" do
      def on_error
        { "allow" => [ "bad" ] }
      end

      it "keeps the row" do
        result = run

        expect([ result.status, result.errors.map(&:line) ]).to eq([ :completed_with_errors, [ 3 ] ])
        expect(events).to include([ :write_rows, [ 2, 3, 4 ] ])
      end
    end

    context "when a row has errors of several actions" do
      before do
        stub_const("RejectB", validator(:row) do |row, _result|
          next unless row.attributes[:email].start_with?("b")

          row.add_error(code: :minor, message: "m").add_error(code: :major, message: "M")
        end)
      end

      def on_error
        { "default" => "abort", "allow" => [ "minor" ], "skip" => [ "major" ] }
      end

      it "applies the worst one and records every error" do
        result = run

        expect([ result.status, result.errors.map(&:code) ]).to eq([ :completed_with_errors, %i[ minor major ] ])
        expect(events).to include([ :write_rows, [ 2, 4 ] ])
      end
    end
  end

  describe "raised errors" do
    def config
      { "validators" => { "row" => [ { "class" => "RaisingValidator" } ] }, "on_error" => "skip" }
    end

    it "turns a RowError into an error of its row and keeps running the other checks" do
      stub_const("RaisingValidator", validator(:row) { |row, _result| raise ApplicationImport::Errors::RowError.new("nope", line: row.line, column: :email, code: :nope) })

      result = run

      expect(result.errors.map { |e| [ e.line, e.column, e.code ] }).to eq([ [ 2, "email", :nope ], [ 3, "email", :nope ] ])
      expect(events).to include([ :validate_row, 2 ])
    end
  end

  describe "rows checks" do
    def content
      "email\na@x.io\nb@x.io\na@x.io\n"
    end

    def config
      { "validators" => { "rows" => [ { "class" => "SeenValidator" } ] }, "on_error" => "skip" }
    end

    it "run per row with the run's cache to keep state across rows" do
      stub_const("SeenValidator", validator(:rows) do |row, _result, cache|
        seen = cache[:seen] ||= {}
        first = seen[row.attributes[:email]] ||= row.line
        row.add_error(code: :duplicate, message: "duplicates line #{first}") if first != row.line
      end)

      result = run

      expect(result.errors.map { |e| [ e.line, e.code, e.message ] }).to eq([ [ 4, :duplicate, "duplicates line 2" ] ])
      expect(events).to include([ :write_rows, [ 2, 3 ] ])
    end

    it "can flag earlier rows with a RowsError" do
      stub_const("SeenValidator", validator(:rows) do |row, _result, cache|
        first = (cache[:seen] ||= {})[row.attributes[:email]] ||= row.line
        raise ApplicationImport::Errors::RowsError.new("dup", lines: [ first, row.line ], code: :duplicate) if first != row.line
      end)

      result = run

      expect(result.errors.map(&:line)).to eq([ 4, 2 ])
      expect(events).to include([ :verify, [ 3 ] ], [ :write_rows, [ 3 ] ])
    end

    it "shares one cache, per run, between rows validators and handler.validate_rows" do
      caches = []
      stub_const("SeenValidator", validator(:rows) { |_row, _result, cache| (cache[:count] = cache.fetch(:count, 0) + 1) && caches << cache })
      RowsSpecHandler.define_method(:validate_rows) { |_row, _result, cache| caches << cache }

      2.times { run }

      expect(caches.first(6).map(&:object_id).uniq.size).to eq(1)
      expect(caches.last).to eq(count: 3)
      expect(caches.first).not_to be(caches.last)
    end
  end

  describe "verify" do
    def config
      { "validators" => { "verify" => [ { "class" => "TotalValidator" } ] }, "on_error" => "skip" }
    end

    it "runs once on the kept rows and can drop rows by line" do
      stub_const("TotalValidator", validator(:verify) do |rows, _result|
        raise ApplicationImport::Errors::RowError.new("last", line: rows.last.line, code: :late)
      end)

      result = run

      expect(result.errors.map { |e| [ e.line, e.code ] }).to eq([ [ 3, :late ] ])
      expect(events).to include([ :write_rows, [ 2 ] ])
    end

    it "records errors on unknown lines as an ArgumentError" do
      stub_const("TotalValidator", validator(:verify) { |_rows, _result| raise ApplicationImport::Errors::RowError.new("x", line: 99) })

      expect { run }.to raise_error(ArgumentError, "no row on line 99")
    end
  end

  describe "read_headers" do
    it "maps headers given up front by the reader before processing" do
      stub_const("UpfrontReader", Class.new(ApplicationImport::Readers::Csv) do
        def read_headers
          [ "email" ]
        end
      end)
      mapper = instance_spy(ApplicationImport::HeaderMapper, call: ApplicationImport::HeaderMap.new(column_keys: [ :email ], indexes: { 0 => :email }))
      allow(ApplicationImport::HeaderMapper).to receive(:new).and_return(mapper)
      definition = ApplicationImport::Definition.new(:users, {
        "handler" => "RowsSpecHandler", "file" => { "reader" => "UpfrontReader" }, "columns" => { "email" => nil }
      })

      RowsSpecRunner.new(definition, ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new(content)), logger: nil).call

      expect(mapper).to have_received(:call).with([ "email" ], anything).once
      expect(events.first).to eq([ :map_row, 2 ])
    end
  end
end
