RSpec.describe ApplicationImport::Runner do
  let(:source) { Object.new }
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
    Class.new(described_class) { define_method(:process) { instance_exec(&process) } }
      .new(definition, source, context: { user_id: 1 })
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

  it "does not implement process yet" do
    plain = described_class.new(definition, source)

    expect { plain.call }.to raise_error(NotImplementedError, "ApplicationImport::Runner#process")
  end
end
