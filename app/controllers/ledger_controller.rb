
class LedgerController < ApplicationController
  before_action :validate_transaction!, only: %i[credit debit]

  def credit
    balance = LedgerService.credit(
        user_id: @transaction_user_id,
        amount: @transaction_amount
    )

    render_balance(@transaction_user_id, balance)
    rescue LedgerService::BalanceOverflow
    render_error(:conflict, "balance_overflow", "Balance limit exceeded")
  end

  def debit
    balance = LedgerService.debit(
      user_id: @transaction_user_id,
      amount: @transaction_amount
    )

    render_balance(@transaction_user_id, balance)
  rescue LedgerService::UserNotFound
    render_error(:not_found, "user_not_found", "User not found")
  rescue LedgerService::InsufficientFunds
    render_error(:conflict, "insufficient_funds", "Insufficient funds")
  end

  def balance
    user_id = params[:user_id]

    unless user_id.is_a?(String) &&
           TransactionRequestValidator::USER_ID_PATTERN.match?(user_id)
      return render_error(:bad_request, "invalid_request", "Invalid user_id")
    end

    account = Account.find_by(user_id: user_id)

    return render_error(:not_found, "user_not_found", "User not found") unless account

    render_balance(user_id, account.balance)
  end

  private

  def validate_transaction!
    unless request.media_type == "application/json"
      return render_error(
        :bad_request,
        "invalid_request",
        "Content-Type must be application/json"
      )
    end

    body = JSON.parse(request.raw_post)

    unless body.is_a?(Hash)
      return render_error(
        :bad_request,
        "invalid_request",
        "JSON body must be an object"
      )
    end

    error = TransactionRequestValidator.validate(
      user_id: body["user_id"],
      amount: body["amount"]
    )

    if error
      return render json: error, status: :bad_request
    end

    @transaction_user_id = body["user_id"]
    @transaction_amount = body["amount"]
  rescue JSON::ParserError
    render_error(:bad_request, "invalid_request", "Malformed JSON")
  end

  def render_balance(user_id, balance)
    render json: {
      user_id: user_id,
      balance: balance
    }, status: :ok
  end

  def render_error(status, code, message)
    render json: {
      error: code,
      message: message
    }, status: status
  end
end
