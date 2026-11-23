RSpec.describe Logs::ServiceLog do
  let(:io) { StringIO.new }
  let(:test_logger) do
    ActiveSupport::Logger.new(io).tap do |logger|
      logger.formatter = ->(severity, _time, _progname, message) { "#{severity} #{message}\n" }
    end
  end
  let(:host_class) do
    concern = described_class
    Class.new do
      include concern

      class << self
        def name
          "Importer"
        end
      end

      def service_id
        "Importer#fixed-id"
      end
    end
  end
  let(:service) { host_class.new }

  before { allow(Rails).to receive(:logger).and_return(test_logger) }

  describe "level helpers" do
    {
      debug: "DEBUG",
      info: "INFO",
      warn: "WARN",
      error: "ERROR",
      fatal: "FATAL"
    }.each do |level, severity|
      it "##{level} logs at #{severity} with the service prefix" do
        service.send(level, "step done")

        expect(io.string).to eq("#{severity} [Importer#fixed-id] step done\n")
      end
    end

    it "stringifies non-string messages" do
      service.send(:info, { rows: 3 })

      expect(io.string).to eq("INFO [Importer#fixed-id] {rows: 3}\n")
    end

    it "skips levels below the logger level without building the message" do
      test_logger.level = :warn
      message = instance_double(String)
      allow(message).to receive(:to_s)

      service.send(:info, message)

      expect(io.string).to be_empty
      expect(message).not_to have_received(:to_s)
    end
  end

  describe "#log_prefix" do
    it "wraps the service id in brackets" do
      expect(service.send(:log_prefix)).to eq("[Importer#fixed-id]")
    end
  end

  describe "#logger" do
    it "defaults to Rails.logger and is memoized" do
      first = service.send(:logger)

      expect(first).to be(test_logger)
      expect(service.send(:logger)).to be(first)
    end

    it "can be overridden by the including class" do
      custom_io = StringIO.new
      custom_class = Class.new(host_class) do
        define_method(:logger) { @logger ||= ActiveSupport::Logger.new(custom_io) }
      end

      custom_class.new.send(:info, "to custom")

      expect([ custom_io.string, io.string ]).to eq([ "[Importer#fixed-id] to custom\n", "" ])
    end
  end

  describe "placement" do
    it "defines the helpers on the concern itself, not on each including class" do
      helpers = %i[debug info warn error fatal logger log_prefix]

      expect(described_class.private_instance_methods(false)).to match_array(helpers)
      expect(host_class.private_instance_methods(false) & helpers).to be_empty
    end

    it "lets an including class override a helper and call super" do
      overriding = Class.new(host_class) do
        private

        def log_prefix
          "#{super} [tenant=a]"
        end
      end

      overriding.new.send(:info, "step done")

      expect(io.string).to eq("INFO [Importer#fixed-id] [tenant=a] step done\n")
    end
  end

  describe "visibility" do
    it "adds the helpers as private methods only" do
      helpers = %i[debug info warn error fatal logger log_prefix]

      expect([ host_class.private_instance_methods & helpers, host_class.public_instance_methods & helpers ])
        .to contain_exactly(match_array(helpers), [])
    end
  end
end
