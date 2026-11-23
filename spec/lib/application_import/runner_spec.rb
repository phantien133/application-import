RSpec.describe ApplicationImport::Runner do
  let(:source) { Object.new }
  let(:definition) do
    ApplicationImport::Definition.new(:users, {
      "handler" => "ImportTestHandler",
      "file" => { "validator" => "ImportTestFileValidator" },
      "columns" => { "email" => nil }
    })
  end
  let(:file_validation) { ->(_source, _result) { } }
  let(:processor) { -> { result.increment(:total) } }
  let(:runner) do
    process = processor
    Class.new(described_class) { define_method(:process) { instance_exec(&process) } }
      .new(definition, source, context: { user_id: 1 })
  end

  before do
    stub_const("ImportTestHandler", Class.new(ApplicationImport::Handler) do
      def calls
        @calls ||= []
      end

      def validate_file_meta(source, result)
        calls << [ :validate_file_meta, source, result.errors.size ]
      end

      def after_import(result)
        calls << [ :after_import, result ]
      end
    end)
    validation = file_validation
    stub_const("ImportTestFileValidator", Class.new(ApplicationImport::FileValidator) do
      define_method(:call) { |source, result| validation.call(source, result) }
    end)
  end

  it "builds the configured handler with the context and an empty result" do
    expect([ runner.handler.class, runner.handler.context, runner.result.errors ]).to eq([ ImportTestHandler, { user_id: 1 }, [] ])
  end

  it "runs the file validator, the handler hook, process, then after_import and returns the result" do
    result = runner.call

    expect([ result, result.status, result.stats[:total] ]).to eq([ runner.result, :completed, 1 ])
    expect(runner.handler.calls).to eq([ [ :validate_file_meta, source, 0 ], [ :after_import, result ] ])
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
      ImportTestHandler.define_method(:validate_file_meta) { |_source, result| result.add_file_error(:forbidden, "no") }

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

  it "does not implement process yet" do
    plain = described_class.new(definition, source)

    expect { plain.call }.to raise_error(NotImplementedError, "ApplicationImport::Runner#process")
  end
end
