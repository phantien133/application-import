# Debug lines of a run (level debug): start, steps, encoding, headers, row actions,
# writes. Only checked for presence, not exact wording.
RSpec.describe "ApplicationImport debug logging" do # rubocop:disable RSpec/DescribeClass
  let(:log) { StringIO.new }
  let(:logger) { ActiveSupport::Logger.new(log).tap { |l| l.formatter = ->(severity, _, _, msg) { "#{severity} #{msg}\n" } } }

  def run(content, level: :debug, **config)
    logger.level = level
    definition = ApplicationImport::Definition.new(:users, { "columns" => { "email" => { "required" => true } } }.merge(config))
    ApplicationImport.run(definition, StringIO.new(content), filename: "u.csv", logger:)
  end

  it "logs the run's settings, each step, the encoding, the header mapping and the write" do
    run("email\na@x.io\n")

    expect(log.string).to include(
      "DEBUG [ApplicationImport::Runner:users] start u.csv: reader Csv, output raw, stream false, dry_run false, row_errors first",
      "step validate_file", "step read_headers", "step process", "step verify", "step write_rows",
      "reading as UTF-8, newlines normalized", "headers mapped: email -> email", "writing 1 rows"
    )
  end

  it "logs the action taken for a row with errors" do
    run("email\n,x\nb@x.io\n", on_error: "skip")

    expect(log.string).to include("line 2: required -> skip")
  end

  it "logs nothing at debug level when the logger level is info" do
    run("email\na@x.io\n", level: :info)

    expect(log.string).not_to include("DEBUG")
  end

  it "does not build debug messages when debug is off" do
    logger.level = :info
    component = Class.new do
      include ApplicationImport::Logging

      def initialize(logger)
        @logger = logger
      end
    end.new(logger)

    expect { component.send(:debug) { raise "built" } }.not_to raise_error
  end
end
