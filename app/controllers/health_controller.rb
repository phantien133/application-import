# JSON health check through the app's own stack (ApplicationController,
# ApiResponse envelope, ErrorHandling). Rails' built-in GET /up stays as the
# plain liveness probe for load balancers.
class HealthController < ApplicationController
  def show
    render_success({ status: "ok" }, meta: { time: Time.current.iso8601 })
  end
end
