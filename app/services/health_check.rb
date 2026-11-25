# Readiness of the app's dependencies, for GET /health:
#   database -> SELECT 1 on the primary connection
#   redis    -> PING through Rails.cache, when it is a Redis cache store; "skipped"
#               otherwise (e.g. :null_store in test)
# Each check reports status "ok" / "error" / "skipped" and its duration in ms. A failure
# is reported through Rails.error; only the error class is returned (the endpoint is
# public, messages can name hosts).
#
#   HealthCheck.call # => { ok: true, checks: { database: { status: "ok", duration_ms: 1.2 }, ... } }
class HealthCheck < ApplicationService
  CHECKS = %i[ database redis ].freeze

  def call
    checks = CHECKS.index_with { |name| run(name) }
    { ok: checks.values.none? { |check| check[:status] == "error" }, checks: }
  end

  private

  def run(name)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status = send(:"check_#{name}")
    { status:, duration_ms: elapsed_ms(started) }
  rescue => e
    Rails.error.report(e, handled: true, context: { health_check: name })
    warn("#{name} check failed: #{e.class}")
    { status: "error", duration_ms: elapsed_ms(started), error: e.class.name }
  end

  def check_database
    ActiveRecord::Base.connection.select_value("SELECT 1")
    "ok"
  end

  def check_redis
    store = Rails.cache
    return "skipped" unless store.respond_to?(:redis)

    store.redis.with(&:ping)
    "ok"
  end

  def elapsed_ms(started)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
  end
end
