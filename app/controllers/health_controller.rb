# Readiness check through the app's own stack (ApplicationController, ApiResponse
# envelope, ErrorHandling): database and Redis (see HealthCheck).
#   200 { data: { status: "ok", checks: }, meta: { time: } }
#   503 { error: { code: "service_unavailable", message:, details: { checks: } } }
# For monitoring and alerts only. Rails' built-in GET /up stays the liveness probe of
# Kamal and load balancers: a database outage must not get healthy containers restarted.
class HealthController < ApplicationController
  def show
    health = HealthCheck.call
    return render_success({ status: "ok", checks: health[:checks] }, meta: { time: Time.current.iso8601 }) if health[:ok]

    render_error(code: :service_unavailable, message: "Some dependencies are unavailable", status: :service_unavailable,
      details: { checks: health[:checks] })
  end
end
