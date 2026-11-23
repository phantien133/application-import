class ApplicationError < StandardError
  attr_reader :error_message, :code, :status, :details, :origin_error

  # origin_error: the exception being wrapped (Rails or a library). Its message
  # (and details, if a subclass knows how to extract them) are used unless
  # message/details are given explicitly, so errors that are already well
  # described upstream don't need their text re-mapped here.
  def initialize(message = nil, code: default_code, status: default_status, details: nil, origin_error: nil)
    @origin_error = origin_error
    @error_message = message || format_origin_message(origin_error)
    super(@error_message)
    @code = code
    @status = status
    @details = details || format_origin_details(origin_error)
  end

  private

  def default_code
    self.class.name.split("::").last.underscore.to_sym
  end

  def default_status
    :internal_server_error
  end

  # Override in subclasses to adapt a specific library's error format.
  def format_origin_message(error)
    error&.message
  end

  # Validation-style errors (ActiveRecord::RecordInvalid/RecordNotSaved, or any
  # library error exposing a `record` with ActiveModel errors) report the
  # per-attribute messages as details.
  def format_origin_details(error)
    record = error.record if error.respond_to?(:record)
    return unless record.respond_to?(:errors) && record.errors.any?

    record.errors.to_hash
  end
end
