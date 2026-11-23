class ForbiddenError < ApplicationError
  private

  def default_status
    :forbidden
  end
end
