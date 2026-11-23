# Maps exceptions to JSON error responses (see ApiResponse).
#
# Framework errors (every ActiveRecord::ActiveRecordError, plus
# ActionController::ParameterMissing) share one handler instead of one handler
# per class:
#   - status:  Rails' own mapping, config.action_dispatch.rescue_responses
#              (RecordNotFound => 404, RecordInvalid => 422, StaleObjectError => 409, ...)
#   - code:    the exception class name, e.g. :record_not_found, :record_invalid
#   - message: the exception's own message (via ApplicationError origin_error)
#   - details: per-attribute errors when the error carries a record
# Errors Rails maps to 5xx (or does not map, e.g. StatementInvalid whose message
# contains SQL) go to the generic 500 handler and never expose their message.
# Map more classes with config.action_dispatch.rescue_responses["Some::Error"] = :conflict.
#
# rescue_from handlers are searched bottom-up, so the generic StandardError
# handler is registered first and specific ones after it.
module ErrorHandling
  extend ActiveSupport::Concern
  include ApiResponse

  included do
    rescue_from StandardError, with: :handle_unexpected_error
    rescue_from ApplicationError, with: :render_application_error
    rescue_from ActiveRecord::ActiveRecordError, ActionController::ParameterMissing, with: :handle_framework_error
  end

  private

  def handle_framework_error(error)
    status = framework_status_for(error)
    return handle_unexpected_error(error) if Rack::Utils.status_code(status) >= 500

    code = error.class.name.demodulize.underscore.to_sym
    render_application_error(ClientError.new(origin_error: error, code:, status:))
  end

  # First ancestor of the error class that Rails maps to a status.
  def framework_status_for(error)
    responses = ActionDispatch::ExceptionWrapper.rescue_responses
    mapped = error.class.ancestors.find { |klass| responses.key?(klass.name) }
    mapped ? responses[mapped.name] : :internal_server_error
  end

  # Unknown errors: keep Rails' debug page in development, otherwise report the
  # original exception and answer with a generic 500 that leaks no internals
  # (explicit message wins over origin_error.message).
  def handle_unexpected_error(error)
    raise error if Rails.env.development?

    Rails.error.report(error, handled: true)
    render_application_error(UnexpectedError.new("Internal server error", origin_error: error))
  end
end
