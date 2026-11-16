class TransactionRequestValidator
  MAX_AMOUNT = 1_000_000_000
  USER_ID_PATTERN = /\A[A-Za-z0-9_-]{1,64}\z/

  def self.validate(params)
    user_id = params[:user_id]
    amount = params[:amount]

    unless user_id.is_a?(String) &&
           USER_ID_PATTERN.match?(user_id)
      return {
        error: "invalid_request",
        message: "Invalid user_id"
      }
    end

    unless amount.instance_of?(Integer) &&
           amount.between?(1, MAX_AMOUNT)
      return {
        error: "invalid_request",
        message: "Amount must be an integer between 1 and 1000000000"
      }
    end

    nil
  end
end