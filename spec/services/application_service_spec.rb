RSpec.describe ApplicationService do
  let(:log) { StringIO.new }
  let(:service_class) do
    Class.new(described_class) do
      class << self
        def name
          "Greeter"
        end
      end

      def initialize(name, punctuation: "!")
        super()
        @name = name
        @punctuation = punctuation
      end

      def call
        info("greeting #{@name}")
        "Hello #{@name}#{@punctuation}"
      end
    end
  end

  before { allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log)) }

  describe ".call" do
    it "builds an instance with positional and keyword args and runs #call" do
      expect(service_class.call("Ann", punctuation: "?")).to eq("Hello Ann?")
    end
  end

  describe "#call" do
    it "must be implemented by subclasses" do
      expect { described_class.new.call }.to raise_error(NotImplementedError, /must implement #call/)
    end
  end

  describe "#service_id" do
    let(:uuid_v7) { /\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}/ }

    def uuid_of(service)
      service.service_id.split("#", 2).last
    end

    # UUID v7: the first 48 bits are the Unix time in milliseconds.
    def uuid_time(service)
      Time.zone.at(uuid_of(service).delete("-")[0, 12].to_i(16) / 1000.0)
    end

    it "is the class name plus a UUID v7 (RFC 9562 variant)" do
      expect(service_class.new("Ann").service_id).to match(/\AGreeter##{uuid_v7.source}\z/)
    end

    it "uses the full name of namespaced classes" do
      stub_const("Billing::ChargeCard", Class.new(described_class))

      expect(Billing::ChargeCard.new.service_id).to match(/\ABilling::ChargeCard##{uuid_v7.source}\z/)
    end

    it "is memoized per instance" do
      service = service_class.new("Ann")

      expect(service.service_id).to equal(service.service_id)
    end

    it "differs between instances" do
      expect(service_class.new("A").service_id).not_to eq(service_class.new("B").service_id)
    end

    it "stays unique across many instances" do
      ids = Array.new(1_000) { service_class.new("x").service_id }

      expect(ids.uniq.size).to eq(1_000)
    end

    # Generated lazily: the timestamp is the first call to #service_id, not .new.
    it "embeds the time of its first access" do
      expect(uuid_time(service_class.new("Ann"))).to be_within(5.seconds).of(Time.current)
    end

    it "sorts in generation order across milliseconds" do
      first = uuid_of(service_class.new("A"))
      sleep 0.002
      second = uuid_of(service_class.new("B"))

      expect([ second, first ].sort).to eq([ first, second ])
    end
  end

  describe "logging" do
    it "prefixes messages with the service id" do
      service = service_class.new("Ann")
      service.call

      expect(log.string).to eq("[#{service.service_id}] greeting Ann\n")
    end

    it "keeps the log helpers private" do
      expect(service_class.private_instance_methods).to include(:debug, :info, :warn, :error, :fatal, :logger, :log_prefix)
    end

    it "does not build messages for disabled levels" do
      Rails.logger.level = :info
      service = service_class.new("Ann")

      service.send(:debug, "hidden")

      expect(log.string).to be_empty
    end
  end
end
