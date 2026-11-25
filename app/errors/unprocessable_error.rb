# A well-formed request whose content cannot be processed (422).
class UnprocessableError < ApplicationError
  private

  def default_status
    :unprocessable_content
  end
end
