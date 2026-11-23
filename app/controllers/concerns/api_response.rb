# JSON envelope shared by every API controller.
#
#   success: { "data": ..., "meta": ... }
#   error:   { "error": { "code": ..., "message": ..., "details": ... } }
module ApiResponse
  extend ActiveSupport::Concern

  private

  def render_success(data = nil, status: :ok, meta: nil)
    render json: { data:, meta: }.compact, status:
  end

  def render_error(code:, message:, status:, details: nil)
    render json: { error: { code:, message:, details: }.compact }, status:
  end

  def render_application_error(error)
    render_error(code: error.code, message: error.message, status: error.status, details: error.details)
  end
end
