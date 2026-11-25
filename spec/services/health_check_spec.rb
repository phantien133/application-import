RSpec.describe HealthCheck do
  it_behaves_like "an application service"

  describe "#call" do
    subject(:health) { described_class.new.call }

    let(:redis) { instance_double(Redis) }

    def redis_cache(redis)
      store = ActiveSupport::Cache::NullStore.new
      store.define_singleton_method(:redis) { redis }
      store
    end

    before { allow(Rails.error).to receive(:report) }

    it "is ok with the database up and Redis skipped without a Redis cache store" do
      expect(health).to match(ok: true, checks: {
        database: { status: "ok", duration_ms: a_kind_of(Float) },
        redis: { status: "skipped", duration_ms: a_kind_of(Float) }
      })
    end

    it "pings Redis through a Redis cache store" do
      allow(redis).to receive(:with).and_yield(redis)
      allow(redis).to receive(:ping).and_return("PONG")
      allow(Rails).to receive(:cache).and_return(redis_cache(redis))

      expect(health[:checks][:redis]).to include(status: "ok")
      expect(redis).to have_received(:ping)
    end

    it "fails when Redis does not answer" do
      allow(redis).to receive(:with).and_raise(Redis::CannotConnectError, "redis host down")
      allow(Rails).to receive(:cache).and_return(redis_cache(redis))

      expect(health).to include(ok: false)
      expect(health[:checks][:redis]).to include(status: "error", error: "Redis::CannotConnectError")
    end

    it "fails when the database query fails, and reports the error" do
      error = ActiveRecord::ConnectionNotEstablished.new("db host down")
      allow(ActiveRecord::Base).to receive(:connection).and_raise(error)

      expect(health).to include(ok: false)
      expect(health[:checks][:database]).to include(status: "error", error: "ActiveRecord::ConnectionNotEstablished")
      expect(Rails.error).to have_received(:report).with(error, handled: true, context: { health_check: :database })
    end
  end
end
