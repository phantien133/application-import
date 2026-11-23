RSpec.describe ApplicationImport::Runner do
  let(:source) { ApplicationImport::Source.new(filename: "users.csv", io: StringIO.new(content)) }
  let(:definition) do
    ApplicationImport::Definition.new(:users, {
      "handler" => "ImportTestHandler",
      "file" => { "checker" => "ImportTestFileChecker" },
      "columns" => { "email" => nil },
      "validators" => { "file" => [ { "class" => "ImportTestFileStageValidator", "tag" => "v1" } ] },
      "on_error" => on_error_config
    })
  end
  let(:file_validation) { ->(_source, _result) { } }
  let(:processor) { -> { result.increment(:total) } }
  let(:runner) do
    process = processor
    read = stub_read_file? && -> { }
    Class.new(described_class) do
      define_method(:process) { instance_exec(&process) }
      define_method(:read_file) { instance_exec(&read) } if read
    end.new(definition, source, context: { user_id: 1 })
  end

  def content
    "email\na@example.com\nb@example.com\n"
  end

  # Orchestration examples stub the read step; "reading the file" uses the real reader.
  def stub_read_file?
    true
  end

  def stage_log
    @stage_log ||= []
  end

  def on_error_config
    { "allow" => [ "duplicate" ], "skip" => [ "required" ] }
  end

  before do
    stub_const("ImportTestHandler", Class.new(ApplicationImport::Handler) do
      def calls
        @calls ||= []
      end

      def validate_file(source, result)
        calls << [ :validate_file, source, result.errors.size ]
      end

      def after_import(result)
        calls << [ :after_import, result ]
      end
    end)
    log = stage_log
    stub_const("ImportTestFileStageValidator", Class.new(ApplicationImport::Validators::FileValidator) do
      define_method(:call) { |source, _result| log << [ options[:tag], source, object_id ] }
    end)
    validation = file_validation
    stub_const("ImportTestFileChecker", Class.new(ApplicationImport::FileChecker) do
      define_method(:call) { |source, result| validation.call(source, result) }
    end)
  end

  it "defaults the logger to ApplicationImport.logger and hands it to the file checker" do
    loggers = []
    ImportTestFileChecker.define_method(:call) { |_source, _result| loggers << logger }
    runner.call

    expect([ runner.logger, loggers ]).to eq([ ApplicationImport.logger, [ ApplicationImport.logger ] ])
  end

  it "uses an injected logger" do
    logger = ActiveSupport::Logger.new(nil)

    expect(described_class.new(definition, source, logger:).logger).to be(logger)
  end

  it "builds the configured handler with the context and an empty result" do
    expect([ runner.handler.class, runner.handler.context, runner.result.errors ]).to eq([ ImportTestHandler, { user_id: 1 }, [] ])
  end

  it "runs the file validator, the handler hook, process, then after_import and returns the result" do
    result = runner.call

    expect([ result, result.status, result.stats[:total] ]).to eq([ runner.result, :completed, 1 ])
    expect(runner.handler.calls).to eq([ [ :validate_file, source, 0 ], [ :after_import, result ] ])
  end

  context "when the file validator adds a file error" do
    let(:file_validation) { ->(_source, result) { result.add_file_error(:invalid_format, "must be csv") } }
    let(:processor) { -> { raise "process must not run" } }

    it "halts before process and still returns the result" do
      result = runner.call

      expect([ result.status, result.errors.map(&:code) ]).to eq([ :failed, [ :invalid_format ] ])
      expect(runner.handler.calls.last).to eq([ :after_import, result ])
    end
  end

  context "when the handler rejects the file" do
    let(:processor) { -> { raise "process must not run" } }

    it "halts with the handler error" do
      ImportTestHandler.define_method(:validate_file) { |_source, result| result.add_file_error(:forbidden, "no") }

      expect(runner.call.errors.map(&:code)).to eq([ :forbidden ])
    end
  end

  context "when process halts early after a row error" do
    let(:processor) do
      lambda do
        result.increment(:total).add_row_error(line: 2, column: :email, code: :required, message: "Email is required")
        halt!
        result.increment(:total)
      end
    end

    it "keeps everything collected before halting" do
      result = runner.call

      expect([ result.status, result.stats[:total], result.errors.map(&:line) ]).to eq([ :failed, 1, [ 2 ] ])
      expect(runner.handler.calls.last).to eq([ :after_import, result ])
    end
  end

  context "when process raises a FileError" do
    let(:processor) do
      -> { raise ApplicationImport::Errors::FileError.new("bad bytes", code: :invalid_encoding) }
    end

    it "adds a file-level error and halts" do
      result = runner.call

      expect([ result.status, result.errors.map(&:to_h) ]).to eq([ :failed, [ { code: :invalid_encoding, message: "bad bytes" } ] ])
    end
  end

  describe "row errors" do
    let(:processor) do
      lambda do
        actions = [
          [ 2, :required ], [ 3, :duplicate ], [ 4, :invalid_type ], [ 5, :required ]
        ].map do |line, code|
          result.increment(:total)
          handle_error(ApplicationImport::Errors::RowError.new("#{code} on #{line}", line:, column: :email, code:))
        end
        result.add_records([ actions ])
      end
    end

    it "continues on allowed and skipped codes and halts on others with the default abort" do
      result = runner.call

      expect([ result.status, result.stats[:total], result.errors.map(&:line) ]).to eq([ :failed, 3, [ 2, 3, 4 ] ])
      expect(result.records).to be_empty
      expect(runner.handler.calls.last).to eq([ :after_import, result ])
    end

    context "when the default is skip" do
      def on_error_config
        { "default" => "skip", "allow" => [ "duplicate" ] }
      end

      it "returns the action for each error and completes with errors" do
        result = runner.call

        expect([ result.status, result.stats[:total], result.records ])
          .to eq([ :completed_with_errors, 4, [ %i[ skip allow skip skip ] ] ])
      end
    end
  end

  context "when a step raises a RowsError" do
    def on_error_config
      "skip"
    end
    let(:processor) do
      -> { raise ApplicationImport::Errors::RowsError.new("duplicate email", lines: [ 2, 5 ], columns: [ :email ], code: :duplicate) }
    end

    it "records it with every line in details and still returns the result" do
      result = runner.call

      expect(result.status).to eq(:completed_with_errors)
      expect(result.errors.map(&:to_h)).to eq([
        { line: 2, column: "email", code: :duplicate, message: "duplicate email", details: { lines: [ 2, 5 ], columns: [ "email" ] } }
      ])
      expect(runner.handler.calls.last).to eq([ :after_import, result ])
    end
  end

  context "when a step raises a RowError and on_error aborts" do
    def on_error_config
      "abort"
    end
    let(:processor) { -> { raise ApplicationImport::Errors::RowError.new("Email is required", line: 2, code: :required) } }

    it "halts with the error" do
      expect(runner.call.then { |result| [ result.status, result.errors.map(&:code) ] }).to eq([ :failed, [ :required ] ])
    end
  end

  context "when the file has errors and on_error skips everything" do
    def on_error_config
      "skip"
    end
    let(:processor) { -> { raise ApplicationImport::Errors::FileError.new("bad bytes", code: :invalid_encoding) } }

    it "always halts on file errors" do
      expect(runner.call.status).to eq(:failed)
    end
  end

  it "runs file-stage validators with their options, a new instance per run" do
    2.times { runner.class.new(definition, source).call }

    expect(stage_log.map { |tag, given, _id| [ tag, given ] }).to eq([ [ "v1", source ], [ "v1", source ] ])
    expect(stage_log.map(&:last).uniq.size).to eq(2)
  end

  it "keeps its own frozen copy of the context" do
    context = { user_id: 1 }
    runner = described_class.new(definition, source, context:)

    expect([ runner.context, runner.context.frozen?, runner.handler.context, context.frozen? ])
      .to eq([ { user_id: 1 }, true, runner.context, false ])
    expect(runner.context).not_to equal(context)
  end

  context "when the file validator raises a skipped RowsError" do
    let(:file_validation) do
      ->(_source, _result) { raise ApplicationImport::Errors::RowsError.new("dup", lines: [ 2, 3 ], code: :duplicate) }
    end

    def on_error_config
      "skip"
    end

    it "records the error and still runs the next step" do
      result = runner.call

      expect([ result.status, result.stats[:total], result.errors.map(&:code) ]).to eq([ :completed_with_errors, 1, [ :duplicate ] ])
    end
  end

  context "when a step raises an unhandled exception" do
    let(:processor) { -> { raise "boom" } }

    it "still calls after_import and re-raises" do
      expect { runner.call }.to raise_error(RuntimeError, "boom")
      expect(runner.handler.calls.last).to eq([ :after_import, runner.result ])
    end
  end

  describe "reading the file" do
    let(:processor) { -> { } }

    def stub_read_file?
      false
    end

    it "reads data rows through the definition's reader after validate_file, before process" do
      seen = []
      ImportTestHandler.define_method(:validate_file) { |_source, _result| seen << :validate_file }
      runner.singleton_class.define_method(:process) { seen << [ :process, rows.map(&:line) ] }

      result = runner.call

      expect([ result.status, result.stats[:total], runner.reader.class ]).to eq([ :completed, 2, ApplicationImport::Readers::Csv ])
      expect(runner.rows).to eq([
        ApplicationImport::Row.new(line: 2, attributes: { email: "a@example.com" }, raw: [ "a@example.com" ]),
        ApplicationImport::Row.new(line: 3, attributes: { email: "b@example.com" }, raw: [ "b@example.com" ])
      ])
      expect(seen).to eq([ :validate_file, [ :process, [ 2, 3 ] ] ])
    end

    it "logs how many rows were read" do
      log = StringIO.new
      runner = described_class.new(definition, source, logger: ActiveSupport::Logger.new(log))
      runner.singleton_class.define_method(:process) { nil }
      runner.call

      expect(log.string).to include("[ApplicationImport::Runner:users] read 2 rows from users.csv")
    end

    context "when reading raises a FileError" do
      def content
        "email\n\xFF\n".b
      end

      let(:processor) { -> { raise "process must not run" } }

      it "halts with the file error" do
        result = runner.call

        expect([ result.status, result.errors.map(&:code), runner.rows ]).to eq([ :failed, [ :invalid_encoding ], [] ])
        expect(runner.handler.calls.last).to eq([ :after_import, result ])
      end
    end

    context "when the file checker rejects the file" do
      let(:file_validation) { ->(_source, result) { result.add_file_error(:invalid_name, "bad name") } }

      it "does not read it" do
        runner.call

        expect([ runner.rows, runner.instance_variable_get(:@reader) ]).to eq([ [], nil ])
      end
    end

    context "when a required header is missing" do
      def content
        "name\nAnn\n"
      end

      let(:definition) do
        ApplicationImport::Definition.new(:users, {
          "handler" => "ImportTestHandler", "file" => { "checker" => "ImportTestFileChecker" },
          "columns" => { "email" => { "required" => true }, "name" => nil }
        })
      end
      let(:processor) { -> { raise "process must not run" } }

      it "halts with missing_headers before reading rows" do
        result = runner.call

        expect([ result.status, result.errors.map(&:code), runner.rows ]).to eq([ :failed, [ :missing_headers ], [] ])
        expect(runner.handler.calls.last).to eq([ :after_import, result ])
      end

      context "with a header row only" do
        def content
          "name\n"
        end

        it "reports the header problem rather than the empty file" do
          expect(runner.call.errors.map(&:code)).to eq([ :missing_headers ])
        end
      end
    end

    context "with unknown headers kept" do
      def content
        "Email,Phone\na@example.com,123\n"
      end

      let(:definition) do
        ApplicationImport::Definition.new(:users, {
          "file" => { "checker" => "ImportTestFileChecker", "unknown_headers" => "keep" }, "columns" => { "email" => nil }
        })
      end

      it "passes them through in the row attributes" do
        runner.call

        expect(runner.rows.map(&:attributes)).to eq([ { :email => "a@example.com", "Phone" => "123" } ])
      end
    end

    context "with a custom reader that never calls on_headers" do
      let(:definition) do
        stub_const("PlainReader", Class.new(ApplicationImport::Readers::Base) do
          def headers
            [ "email" ]
          end

          def each
            yield ApplicationImport::Readers::RawRow.new(line: 2, values: [ "a@example.com" ])
            self
          end
        end)
        ApplicationImport::Definition.new(:users, {
          "handler" => "ImportTestHandler", "file" => { "checker" => "ImportTestFileChecker", "reader" => "PlainReader" },
          "columns" => { "email" => { "required" => true } }
        })
      end

      it "maps the headers at the first row" do
        runner.call

        expect(runner.rows.map(&:attributes)).to eq([ { email: "a@example.com" } ])
      end
    end

    it "uses a custom reader from the definition" do
      stub_const("UpcaseReader", Class.new(ApplicationImport::Readers::Csv) do
        private

        def each_record
          super { |line, values| yield line, values.map(&:upcase) }
        end
      end)
      definition = ApplicationImport::Definition.new(:users, {
        "file" => { "checker" => "ImportTestFileChecker", "reader" => "UpcaseReader" }, "columns" => { "email" => nil }
      })
      runner = Class.new(described_class) { define_method(:process) { nil } }.new(definition, source)

      runner.call

      expect(runner.rows.map(&:raw)).to eq([ [ "A@EXAMPLE.COM" ], [ "B@EXAMPLE.COM" ] ])
    end
  end

  it "does not implement process yet" do
    plain = described_class.new(definition, source)

    expect { plain.call }.to raise_error(NotImplementedError, "ApplicationImport::Runner#process")
  end

  describe "reader lifecycle" do
    let(:definition) do
      ApplicationImport::Definition.new(:users, {
        "handler" => "ImportTestHandler", "file" => { "checker" => "ImportTestFileChecker", "reader" => "TrackingReader" },
        "columns" => { "email" => nil }
      })
    end
    let(:processor) do
      log = events
      -> { log << :process }
    end

    before do
      log = events
      stub_const("TrackingReader", Class.new(ApplicationImport::Readers::Csv) do
        define_method(:open) { (log << :open) && self }
        define_method(:close) { (log << :close) && self }
        define_method(:each) { |&block| (log << :read) && super(&block) }
      end)
      ImportTestHandler.define_method(:after_import) { |_result| log << :after_import }
    end

    def events
      @events ||= []
    end

    def stub_read_file?
      false
    end

    it "opens after validate_file, reads, processes, then closes before after_import" do
      log = events
      ImportTestHandler.define_method(:validate_file) { |_source, _result| log << :validate_file }

      runner.call

      expect(events).to eq(%i[ validate_file open read process close after_import ])
    end

    context "when process raises" do
      let(:processor) { -> { raise "boom" } }

      it "still closes the reader" do
        expect { runner.call }.to raise_error("boom")
        expect(events).to eq(%i[ open read close after_import ])
      end
    end

    context "when reading halts on a file error" do
      def content
        "email\n\xFF\n".b
      end

      it "still closes the reader" do
        expect(runner.call.status).to eq(:failed)
        expect(events).to eq(%i[ open read close after_import ])
      end
    end

    context "when validate_file halts" do
      let(:file_validation) { ->(_source, result) { result.add_file_error(:invalid_name, "bad") } }

      it "neither opens nor closes the reader" do
        runner.call

        expect(events).to eq(%i[ after_import ])
      end
    end

    context "when open raises a FileError" do
      it "halts with it and does not close" do
        TrackingReader.define_method(:open) { raise ApplicationImport::Errors::FileError.new("corrupt", code: :unreadable) }

        expect(runner.call.errors.map(&:code)).to eq([ :unreadable ])
        expect(events).to eq(%i[ after_import ])
      end
    end

    context "when close raises" do
      it "logs the failure without hiding the result" do
        TrackingReader.define_method(:close) { raise IOError, "already closed" }
        log = StringIO.new
        runner.instance_variable_set(:@logger, ActiveSupport::Logger.new(log))

        expect(runner.call.status).to eq(:completed)
        expect(log.string).to include("closing the reader failed: IOError: already closed")
      end
    end
  end
end
