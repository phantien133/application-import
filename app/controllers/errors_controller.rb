# Renders errors raised outside controller actions (unknown route, malformed
# request body, ...) with the same JSON envelope as ErrorHandling. Wired as
# config.exceptions_app; Rails reports the exception itself and passes the
# status as the path ("/404"). Inherits ActionController::API, not
# ApplicationController, so a failure here cannot loop through ErrorHandling.
class ErrorsController < ActionController::API
  include ApiResponse

  def show
    status = request.path_info.delete_prefix("/").to_i
    status = 500 unless status.between?(400, 599)
    exception = request.env["action_dispatch.exception"]

    render_error(code: code_for(exception, status), message: message_for(exception, status), status:)
  end

  private

  def code_for(exception, status)
    return :unexpected_error if status >= 500
    return exception.class.name.demodulize.underscore.to_sym if exception&.class&.name

    Rack::Utils::SYMBOL_TO_STATUS_CODE.key(status) || :client_error
  end

  def message_for(exception, status)
    return UnexpectedError::GENERIC_MESSAGE if status >= 500

    exception&.message.presence || Rack::Utils::HTTP_STATUS_CODES.fetch(status, "Client error")
  end
end
