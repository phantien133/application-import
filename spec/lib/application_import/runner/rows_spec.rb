RSpec.describe ApplicationImport::Runner::Rows do
  let(:events) { [] }

  before do
    log = events
    stub_const("RowsSpecRunner", Class.new(ApplicationImport::Runner) { define_method(:write_rows) { log << [ :write_rows, rows.map(&:line) ] } })
    stub_const("RowsSpecHandler", Class.new(ApplicationImport::Handler) do
      define_method(:map_row) { |attributes, row| (log << [ :map_row, row.line ]) && attributes.merge(mapped: true) }
      define_method(:validate_row) { |row, _result| log << [ :validate_row, row.line ] }
      define_method(:validate_rows) { |row, _result, _cache| log << [ :validate_rows, row.line ] }
      define_method(:verify) { |rows, _result, _cache| log << [ :verify, rows.map(&:line) ] }
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

      it "stops the row at its failing check and drops it from verify and write_rows" do
        result = run

        expect([ result.status, result.stats[:invalid] ]).to eq([ :completed_with_errors, 1 ])
        expect(events).to include([ :verify, [ 2, 4 ] ], [ :write_rows, [ 2, 4 ] ])
        expect(events).not_to include([ :validate_row, 3 ], [ :validate_rows, 3 ])
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

  describe "casting" do
    def content
      "email,age,note\na@x.io, 30 ,hi\nb@x.io,old,hi\n"
    end

    def config
      { "file" => { "unknown_headers" => "keep" }, "columns" => { "email" => nil, "age" => { "type" => "integer", "min" => 18 } },
        "on_error" => on_error }
    end

    def on_error
      "skip"
    end

    it "casts declared columns before map_row, leaving kept unknown headers as read" do
      runner = RowsSpecRunner.new(definition, ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new(content)), logger: nil)
      runner.call

      expect(runner.rows.map(&:attributes)).to eq([ { :email => "a@x.io", :age => 30, "note" => "hi", :mapped => true } ])
    end

    it "stops a row with a cast error before map_row (row_errors: first)" do
      result = run

      expect(result.errors.map { |e| [ e.line, e.code, e.column, e.message, e.details ] })
        .to eq([ [ 3, :invalid_type, "age", "age must be an integer", { value: "old" } ] ])
      expect(events).not_to include([ :map_row, 3 ])
    end

    context "with row_errors: all" do
      def on_error
        { "default" => "skip", "row_errors" => "all" }
      end

      it "still runs the next checks after cast errors" do
        run

        expect(events).to include([ :map_row, 3 ], [ :validate_row, 3 ])
      end
    end
  end

  describe "transformers" do
    def content
      "email,age\na@x.io,30\nb@x.io,old\n"
    end

    def config
      { "columns" => { "email" => nil, "age" => { "type" => "integer" } }, "transformers" => transformers, "on_error" => "skip" }
    end

    def transformers
      [ { "class" => "AgeNextYear" }, { "type" => "concat", "from" => %w[ email age_next ], "to" => "label" } ]
    end

    before do
      log = events
      stub_const("AgeNextYear", Class.new(ApplicationImport::Transformers::Base) do
        define_method(:call) { |attributes, row| (log << [ :transform, row.line ]) && { age_next: attributes[:age] + 1 } }
      end)
    end

    it "run in order after cast and before map_row, their results merged and kept as generated keys" do
      runner = RowsSpecRunner.new(definition, ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new(content)), logger: nil)
      runner.call

      row = runner.rows.first
      expect([ row.attributes, row.generated_keys ]).to eq([
        { email: "a@x.io", age: 30, age_next: 31, label: "a@x.io 31", mapped: true }, %i[ age_next label ]
      ])
      expect(events.first(2)).to eq([ [ :transform, 2 ], [ :map_row, 2 ] ])
    end

    it "do not run on a row whose cast failed (row_errors: first)" do
      run

      expect(events).not_to include([ :transform, 3 ])
    end

    it "report errors like other checks" do
      stub_const("AgeNextYear", Class.new(ApplicationImport::Transformers::Base) do
        define_method(:call) { |_attributes, row| raise ApplicationImport::Errors::RowError.new("nope", line: row.line, code: :bad) }
      end)

      expect(run.errors.map { |e| [ e.line, e.code ] }).to eq([ [ 2, :bad ], [ 3, :invalid_type ] ])
    end

    it "may return nil to change nothing" do
      stub_const("AgeNextYear", Class.new(ApplicationImport::Transformers::Base) { define_method(:call) { |_attributes, _row| nil } })
      runner = RowsSpecRunner.new(definition, ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new(content)), logger: nil)
      runner.call

      expect(runner.rows.first.attributes).to eq(email: "a@x.io", age: 30, label: "a@x.io", mapped: true)
    end

    it "see the attributes produced by the transformers before them" do
      seen = []
      stub_const("Spy", Class.new(ApplicationImport::Transformers::Base) { define_method(:call) { |attributes, _row| (seen << attributes.keys) && nil } })
      allow(self).to receive(:transformers).and_return(transformers + [ { "class" => "Spy" } ])

      run

      expect(seen.first).to include(:age_next, :label)
    end

    it "all run and collect their errors with row_errors: all" do
      stub_const("AgeNextYear", Class.new(ApplicationImport::Transformers::Base) do
        define_method(:call) { |_attributes, row| row.add_error(code: :one, message: "1") && nil }
      end)
      stub_const("Second", Class.new(ApplicationImport::Transformers::Base) do
        define_method(:call) { |_attributes, row| row.add_error(code: :two, message: "2") && nil }
      end)
      allow(self).to receive(:config).and_return(config.merge("transformers" => [ { "class" => "AgeNextYear" }, { "class" => "Second" } ],
        "on_error" => { "default" => "skip", "row_errors" => "all" }))

      expect(run.errors.select { |e| e.line == 2 }.map(&:code)).to eq(%i[ one two ])
    end

    it "must return a Hash or nil" do
      stub_const("AgeNextYear", Class.new(ApplicationImport::Transformers::Base) { define_method(:call) { |_attributes, _row| [ 1 ] } })

      expect { run }.to raise_error(TypeError, "AgeNextYear#call must return a Hash or nil")
    end

    context "with output.model" do
      def config
        super.merge("output" => { "model" => "RowsSpecUser" }, "transformers" => [ { "type" => "concat", "from" => [ "email" ], "to" => "label" } ])
      end

      before do
        ActiveRecord::Base.connection.create_table(:rows_spec_users, temporary: true) do |t|
          t.string :email
          t.string :label
        end
        stub_const("RowsSpecUser", Class.new(ApplicationRecord) { self.table_name = "rows_spec_users" })
      end

      it "assigns generated keys the model can set to the record" do
        runner = RowsSpecRunner.new(definition, ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new(content)), logger: nil)
        runner.call

        expect(runner.rows.map { |row| [ row.record.email, row.record.label ] }).to eq([ [ "a@x.io", "a@x.io" ] ])
      end
    end
  end

  describe "mapper" do
    def config
      { "columns" => { "email" => nil, "name" => nil }, "transformers" => [ { "type" => "concat", "from" => %w[ name ], "to" => "label" } ],
        "mapper" => mapper, "on_error" => "skip" }
    end

    def content
      "email,name\na@x.io,Ann\n"
    end

    def mapper
      { "type" => "rename", "attributes" => { "email" => "user_email", "label" => "title" } }
    end

    def mapped_rows
      runner = RowsSpecRunner.new(definition, ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new(content)), logger: nil)
      runner.call
      runner.rows
    end

    it "runs after the transformers and before handler.map_row, its keys not declared kept as generated" do
      row = mapped_rows.first

      expect([ row.attributes, row.generated_keys ]).to eq([ { name: "Ann", user_email: "a@x.io", title: "Ann", mapped: true },
        %i[ label user_email title ] ])
    end

    it "lets validators see the mapped attributes" do
      seen = []
      stub_const("SeeMapped", validator(:row) { |row, _result| seen << row.attributes.keys })
      allow(self).to receive(:config).and_return(config.merge("validators" => { "row" => [ { "class" => "SeeMapped" } ] }))

      run

      expect(seen.first).to include(:user_email, :title)
    end

    context "with a custom mapper" do
      def mapper
        { "class" => "NestMapper", "key" => "profile" }
      end

      before do
        stub_const("NestMapper", Class.new(ApplicationImport::Mappers::Base) do
          define_method(:call) do |attributes, row|
            raise ApplicationImport::Errors::RowError.new("no name", line: row.line, code: :no_name) if attributes[:name].nil?

            { :email => attributes[:email], options[:key].to_sym => { name: attributes[:name] } }
          end
        end)
      end

      it "replaces the attributes with its Hash" do
        expect(mapped_rows.first.attributes).to eq(email: "a@x.io", profile: { name: "Ann" }, mapped: true)
      end

      it "reports raised row errors like other checks" do
        allow(self).to receive(:content).and_return("email,name\na@x.io,\n")

        expect(run.errors.map { |e| [ e.line, e.code ] }).to eq([ [ 2, :no_name ] ])
      end

      it "gets its options, the run's context and logger" do
        seen = []
        NestMapper.define_method(:call) { |attributes, _row| (seen << [ options, context ]) && attributes }
        RowsSpecRunner.new(definition, ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new(content)),
          context: { user_id: 3 }, logger: nil).call

        expect(seen).to eq([ [ { key: "profile" }, { user_id: 3 } ] ])
      end

      it "is not run for a row stopped earlier (row_errors: first)" do
        calls = []
        NestMapper.define_method(:call) { |attributes, row| (calls << row.line) && attributes }
        allow(self).to receive_messages(config: config.merge("columns" => { "email" => nil, "name" => { "required" => true } }),
          content: "email,name\na@x.io,\nb@x.io,Bob\n")

        run

        expect(calls).to eq([ 3 ])
      end

      it "must return a Hash" do
        NestMapper.define_method(:call) { |_attributes, _row| nil }

        expect { run }.to raise_error(TypeError, "NestMapper#call must return a Hash")
      end
    end
  end

  describe "settling" do
    def content
      "email\n" + (1..50).map { |i| "u#{i}@x.io\n" }.join
    end

    it "only settles rows that got new errors, not every row read so far" do
      settled = []
      RowsSpecRunner.define_method(:settle) { |row, **options| (settled << row.line) && super(row, **options) }
      stub_const("FlagTen", validator(:row) { |row, _result| row.add_error(code: :ten, message: "x") if row.line == 10 })
      allow(self).to receive(:config).and_return("validators" => { "row" => [ { "class" => "FlagTen" } ] }, "on_error" => "skip")

      run

      expect(settled).to eq([ 10 ])
    end

    it "settles a row flagged later, from another row's check" do
      stub_const("FlagFirst", validator(:rows) do |row, _result, _cache|
        raise ApplicationImport::Errors::RowsError.new("dup", lines: [ 2 ], code: :dup) if row.line == 10
      end)
      allow(self).to receive(:config).and_return("validators" => { "rows" => [ { "class" => "FlagFirst" } ] }, "on_error" => "skip")

      result = run

      expect([ result.errors.map { |e| [ e.line, e.code ] }, result.stats[:invalid] ]).to eq([ [ [ 2, :dup ] ], 1 ])
      expect(events.find { |event| event.first == :write_rows }.last).not_to include(2)
    end

    it "records the errors of every flagged row before an abort halts" do
      stub_const("FlagMany", validator(:verify) do |_rows, _result, _cache|
        raise ApplicationImport::Errors::RowsError.new("bad", lines: [ 5, 3, 7 ], code: :bad)
      end)
      allow(self).to receive(:config).and_return("validators" => { "verify" => [ { "class" => "FlagMany" } ] })

      result = run

      expect([ result.status, result.errors.map(&:line) ]).to eq([ :failed, [ 3, 5, 7 ] ])
    end

    it "settles the current row first, then the others in line order" do
      stub_const("FlagBack", validator(:rows) do |row, _result, _cache|
        raise ApplicationImport::Errors::RowsError.new("pair", lines: [ row.line, 4, 2 ], code: :pair) if row.line == 6
      end)
      allow(self).to receive(:config).and_return("validators" => { "rows" => [ { "class" => "FlagBack" } ] }, "on_error" => "skip")

      expect(run.errors.map(&:line)).to eq([ 6, 2, 4 ])
    end
  end

  describe "unknown lines" do
    it "raise UnknownLineError in the row stage too, instead of using the current row" do
      stub_const("OffByOne", validator(:row) { |row, _result| raise ApplicationImport::Errors::RowError.new("x", line: row.line - 1) })
      allow(self).to receive(:config).and_return("validators" => { "row" => [ { "class" => "OffByOne" } ] })

      expect { run }.to raise_error(ApplicationImport::Errors::UnknownLineError, /line 1 \(raised by OffByOne\)/)
    end

    it "raise for any unknown line of a RowsError, before adding errors" do
      stub_const("PairCheck", validator(:rows) do |row, _result, _cache|
        raise ApplicationImport::Errors::RowsError.new("pair", lines: [ row.line, 42 ]) if row.line == 3
      end)
      allow(self).to receive(:config).and_return("validators" => { "rows" => [ { "class" => "PairCheck" } ] })

      expect { run }.to raise_error(ApplicationImport::Errors::UnknownLineError, /line 42 \(raised by PairCheck\)/)
    end

    it "accept lines of skipped rows" do
      stub_const("FirstBad", validator(:row) { |row, _result| row.add_error(code: :bad, message: "bad") if row.line == 2 })
      stub_const("FlagFirst", validator(:verify) do |_rows, _result, _cache|
        raise ApplicationImport::Errors::RowError.new("again", line: 2, code: :again)
      end)
      allow(self).to receive(:config).and_return(
        "validators" => { "row" => [ { "class" => "FirstBad" } ], "verify" => [ { "class" => "FlagFirst" } ] }, "on_error" => "skip"
      )

      expect(run.errors.map { |e| [ e.line, e.code ] }).to eq([ [ 2, :bad ], [ 2, :again ] ])
    end
  end

  describe "on_error.row_errors" do
    before do
      stub_const("FirstCheck", validator(:row) { |row, _result| row.add_error(code: :one, message: "1").add_error(code: :two, message: "2") })
      stub_const("SecondCheck", validator(:row) { |row, _result| row.add_error(code: :three, message: "3") })
      stub_const("RowsCheck", validator(:rows) { |row, _result, _cache| row.add_error(code: :four, message: "4") })
    end

    def content
      "email\na@x.io\nb@x.io\n"
    end

    def config
      {
        "validators" => { "row" => [ { "class" => "FirstCheck" }, { "class" => "SecondCheck" } ], "rows" => [ { "class" => "RowsCheck" } ] },
        "on_error" => { "default" => "skip", "row_errors" => row_errors }
      }
    end

    context "with first (default)" do
      def row_errors
        "first"
      end

      it "stops each row after the first check reporting errors, keeping that check's errors" do
        result = run

        expect(result.errors.map { |e| [ e.line, e.code ] }).to eq([ [ 2, :one ], [ 2, :two ], [ 3, :one ], [ 3, :two ] ])
        expect(events).to eq([ [ :map_row, 2 ], [ :map_row, 3 ], [ :verify, [] ], [ :write_rows, [] ] ])
      end

      it "is the default" do
        allow(self).to receive(:config).and_return(config.merge("on_error" => { "default" => "skip" }))

        expect(run.errors.map(&:code)).to eq(%i[ one two one two ])
      end
    end

    context "with all" do
      def row_errors
        "all"
      end

      it "runs every check of the row and collects all its errors before on_error" do
        result = run

        expect(result.errors.select { |e| e.line == 2 }.map(&:code)).to eq(%i[ one two three four ])
        expect(events).to include([ :validate_row, 2 ], [ :validate_rows, 2 ])
        expect(result.stats.values_at(:total, :invalid)).to eq([ 2, 2 ])
      end

      it "still applies the worst action once every check ran" do
        allow(self).to receive(:config).and_return(config.merge("on_error" => { "default" => "abort", "row_errors" => "all" }))

        result = run

        expect([ result.status, result.errors.map(&:line).uniq ]).to eq([ :failed, [ 2 ] ])
        expect(events).to include([ :validate_rows, 2 ])
      end
    end

    context "with an allowed error under first" do
      def config
        { "validators" => { "row" => [ { "class" => "FirstCheck" }, { "class" => "SecondCheck" } ] },
          "on_error" => { "allow" => %w[ one two ] } }
      end

      it "keeps the row but skips its remaining checks" do
        result = run

        expect([ result.status, result.errors.map(&:code).uniq ]).to eq([ :completed_with_errors, %i[ one two ] ])
        expect(events).to include([ :write_rows, [ 2, 3 ] ])
        expect(events).not_to include([ :validate_row, 2 ])
      end
    end
  end

  describe "raised errors" do
    def config
      { "validators" => { "row" => [ { "class" => "RaisingValidator" } ] }, "on_error" => "skip" }
    end

    it "turns a RowError into an error of its row, which then stops (row_errors: first)" do
      stub_const("RaisingValidator", validator(:row) { |row, _result| raise ApplicationImport::Errors::RowError.new("nope", line: row.line, column: :email, code: :nope) })

      result = run

      expect(result.errors.map { |e| [ e.line, e.column, e.code ] }).to eq([ [ 2, "email", :nope ], [ 3, "email", :nope ] ])
      expect(events).not_to include([ :validate_row, 2 ])
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
      stub_const("TotalValidator", validator(:verify) do |rows, _result, _cache|
        raise ApplicationImport::Errors::RowError.new("last", line: rows.last.line, code: :late)
      end)

      result = run

      expect(result.errors.map { |e| [ e.line, e.code ] }).to eq([ [ 3, :late ] ])
      expect(events).to include([ :write_rows, [ 2 ] ])
    end

    it "raises UnknownLineError for a line where no data row starts" do
      stub_const("TotalValidator", validator(:verify) { |_rows, _result, _cache| raise ApplicationImport::Errors::RowError.new("x", line: 99) })

      expect { run }.to raise_error(ApplicationImport::Errors::UnknownLineError,
        "no data row starts on line 99 (raised by TotalValidator); use row.line") { |e| expect([ e.line, e.source ]).to eq([ 99, "TotalValidator" ]) }
    end

    it "gets the cache filled by the rows checks" do
      stub_const("CollectValidator", validator(:rows) { |row, _result, cache| (cache[:emails] ||= []) << row.attributes[:email] })
      seen = []
      stub_const("TotalValidator", validator(:verify) { |_rows, _result, cache| seen << cache[:emails] })
      RowsSpecHandler.define_method(:verify) { |_rows, _result, cache| seen << cache[:emails].size }
      allow(self).to receive(:config).and_return(
        "validators" => { "rows" => [ { "class" => "CollectValidator" } ], "verify" => [ { "class" => "TotalValidator" } ] }
      )

      run

      expect(seen).to eq([ %w[ a@x.io b@x.io ], 2 ])
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
