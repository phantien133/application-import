class ClientError < ApplicationError
  private

  def default_status
    :bad_request
  end
end
