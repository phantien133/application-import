RSpec.describe ApplicationImport::Logging do
  let(:log) { StringIO.new }
  let(:logger) { ActiveSupport::Logger.new(log).tap { |l| l.formatter = ->(severity, _, _, msg) { "#{severity} #{msg}\n" } } }
  let(:component_class) do
    stub_const("ImportLogComponent", Class.new do
      include ApplicationImport::Logging

      attr_reader :definition

      def initialize(logger, definition = nil)
        @logger = logger
        @definition = definition
      end
    end)
  end
  let(:component) { component_class.new(logger) }

  it "exposes the logger publicly and the level helpers privately" do
    expect(component.logger).to be(logger)
    expect(component_class.private_instance_methods).to include(*described_class::LEVELS, :log_prefix)
  end

  it "logs at every level with the class name prefix and returns nil" do
    logger.level = :debug

    results = described_class::LEVELS.map { |level| component.send(level, "hi") }

    expect(results).to all(be_nil)
    expect(log.string.lines.map(&:chomp)).to eq(%w[ DEBUG INFO WARN ERROR FATAL ].map { |s| "#{s} [ImportLogComponent] hi" })
  end

  it "adds the definition name when there is one" do
    component = component_class.new(logger, instance_double(ApplicationImport::Definition, name: :users))
    component.send(:warn, "x")

    expect(log.string).to eq("WARN [ImportLogComponent:users] x\n")
  end

  it "does not build the message below the logger level" do
    logger.level = :error

    component.send(:info, "x")

    expect(log.string).to eq("")
  end

  it "is a no-op without a logger" do
    expect(component_class.new(nil).send(:warn, "x")).to be_nil
  end
end
