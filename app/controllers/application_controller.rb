class ApplicationController < ActionController::API
  before_action :authenticate_request!

  private

  def authenticate_request!
    expected_token = ENV.fetch("API_TOKEN")

    authorization = request.headers["Authorization"]

    unless authorization.is_a?(String)
      return unauthorized!
    end

    match = /\ABearer ([^\s]+)\z/.match(authorization)

    return unauthorized! unless match

    provided_token = match[1]

    unless ActiveSupport::SecurityUtils.secure_compare(
      provided_token,
      expected_token
    )
      return unauthorized!
    end
  end

  def unauthorized!
    render json: {
      error: "unauthorized",
      message: "Invalid or missing authentication token"
    }, status: :unauthorized
  end
end