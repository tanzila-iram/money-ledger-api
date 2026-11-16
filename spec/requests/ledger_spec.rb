
require "rails_helper"

RSpec.describe "Money Ledger API", type: :request do
  let(:token) { "recruitment-test-token" }

  let(:headers) do
    {
      "Authorization" => "Bearer #{token}",
      "Content-Type" => "application/json"
    }
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("API_TOKEN").and_return(token)
  end

  def post_json(path, body, request_headers = headers)
    post path, params: body.to_json, headers: request_headers
  end

  describe "POST /credit" do
    it "creates a new account" do
      post_json "/credit", { user_id: "new_user", amount: 10_000 }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "user_id" => "new_user",
        "balance" => 10_000
      )
      expect(Account.find("new_user").balance).to eq(10_000)
      expect(LedgerEntry.where(user_id: "new_user").count).to eq(1)
    end

    it "adds money to an existing account" do
      LedgerService.credit(user_id: "existing_user", amount: 10_000)

      post_json "/credit", { user_id: "existing_user", amount: 5_000 }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["balance"]).to eq(15_000)
      expect(Account.find("existing_user").balance).to eq(15_000)
      expect(LedgerEntry.where(user_id: "existing_user").count).to eq(2)
    end

    it "ignores extra JSON fields" do
      post_json "/credit", {
        user_id: "extra_user",
        amount: 100,
        note: "ignored"
      }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["balance"]).to eq(100)
    end
  end

  describe "POST /debit" do
    it "decreases the account balance" do
      LedgerService.credit(user_id: "debit_user", amount: 10_000)

      post_json "/debit", { user_id: "debit_user", amount: 3_000 }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["balance"]).to eq(7_000)
      expect(LedgerEntry.where(
        user_id: "debit_user",
        entry_type: "debit"
      ).count).to eq(1)
    end

    it "rejects insufficient funds" do
      LedgerService.credit(user_id: "low_balance_user", amount: 100)

      post_json "/debit", { user_id: "low_balance_user", amount: 200 }

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["error"]).to eq("insufficient_funds")
      expect(Account.find("low_balance_user").balance).to eq(100)
      expect(LedgerEntry.where(user_id: "low_balance_user").count).to eq(1)
    end

    it "returns 404 for a nonexistent user" do
      post_json "/debit", { user_id: "missing_user", amount: 100 }

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq("user_not_found")
      expect(Account.exists?(user_id: "missing_user")).to be(false)
    end
  end

  describe "GET /balance/:user_id" do
    it "returns the current balance" do
      LedgerService.credit(user_id: "balance_user", amount: 1_234)

      get "/balance/balance_user", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "user_id" => "balance_user",
        "balance" => 1_234
      )
    end

    it "returns 404 for a nonexistent user" do
      get "/balance/unknown_user", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq("user_not_found")
    end
  end

  describe "authentication" do
    it "rejects requests without a token" do
      get "/balance/some_user"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("unauthorized")
    end

    it "rejects invalid tokens" do
      get "/balance/some_user", headers: {
        "Authorization" => "Bearer wrong-token"
      }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("unauthorized")
    end
    it "does not access the database for unauthorized requests" do
      sql_queries = []

      subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
        next if payload[:name] == "SCHEMA"
        next if payload[:cached]

        sql_queries << payload[:sql]
      end

      ActiveSupport::Notifications.subscribed(
        subscriber,
        "sql.active_record"
      ) do
        get "/balance/some_user", headers: {
          "Authorization" => "Bearer wrong-token"
        }
      end

      expect(response).to have_http_status(:unauthorized)
      expect(sql_queries).to be_empty
    end
  end

  describe "input validation" do
    [
      ["string amount", "100"],
      ["decimal amount", 100.5],
      ["boolean amount", true],
      ["zero amount", 0],
      ["negative amount", -100],
      ["amount above maximum", 1_000_000_001]
    ].each do |description, amount|
      it "rejects #{description}" do
        post_json "/credit", {
          user_id: "invalid_amount_user",
          amount: amount
        }

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body["error"]).to eq("invalid_request")
        expect(Account.exists?(user_id: "invalid_amount_user")).to be(false)
      end
    end

    it "rejects an invalid user ID" do
      post_json "/credit", {
        user_id: "invalid user!",
        amount: 100
      }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("invalid_request")
    end

    it "does not accept amount from query parameters" do
      post_json "/credit?amount=5000", { user_id: "query_user" }

      expect(response).to have_http_status(:bad_request)
      expect(Account.exists?(user_id: "query_user")).to be(false)
    end

    it "rejects malformed JSON" do
      post "/credit",
           params: '{"user_id":"bad_json","amount":',
           headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("invalid_request")
    end

    it "rejects a JSON array" do
      post_json "/credit", [{ user_id: "array_user", amount: 100 }]

      expect(response).to have_http_status(:bad_request)
      expect(Account.exists?(user_id: "array_user")).to be(false)
    end

    it "rejects non-JSON content types" do
      post "/credit",
           params: '{"user_id":"plain_user","amount":100}',
           headers: {
             "Authorization" => "Bearer #{token}",
             "Content-Type" => "text/plain"
           }

      expect(response).to have_http_status(:bad_request)
      expect(Account.exists?(user_id: "plain_user")).to be(false)
    end
  end
end
