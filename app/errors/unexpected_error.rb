class UnexpectedError < ApplicationError
  GENERIC_MESSAGE = "Internal server error".freeze

  private

  # Server errors never expose the wrapped error's message or details (SQL,
  # hosts, internals); the origin is still reported via Rails.error.
  def format_origin_message(_error)
    GENERIC_MESSAGE
  end

  def format_origin_details(_error)
    nil
  end
end
