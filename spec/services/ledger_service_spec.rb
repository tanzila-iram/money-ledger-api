
require "rails_helper"

RSpec.describe LedgerService, type: :service do
  describe ".credit" do
    it "rolls back the balance when ledger creation fails" do
      user_id = "rollback_credit_user"

      described_class.credit(user_id: user_id, amount: 1_000)

      initial_balance = Account.find(user_id).balance
      initial_entries = LedgerEntry.where(user_id: user_id).count

      allow(LedgerEntry).to receive(:create!)
        .and_raise(ActiveRecord::RecordInvalid)

      expect {
        described_class.credit(user_id: user_id, amount: 500)
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(Account.find(user_id).balance).to eq(initial_balance)
      expect(LedgerEntry.where(user_id: user_id).count).to eq(initial_entries)
    end

    it "does not create an account if ledger creation fails" do
      user_id = "rollback_new_user"

      allow(LedgerEntry).to receive(:create!)
        .and_raise(ActiveRecord::RecordInvalid)

      expect {
        described_class.credit(user_id: user_id, amount: 500)
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(Account.exists?(user_id: user_id)).to be(false)
      expect(LedgerEntry.where(user_id: user_id).count).to eq(0)
    end


    it "rejects credits that exceed the BIGINT balance limit" do
    user_id = "overflow_test_user"
    max_balance = 9_223_372_036_854_775_807

    Account.create!(
        user_id: user_id,
        balance: max_balance
    )

    expect {
        LedgerService.credit(user_id: user_id, amount: 1)
    }.to raise_error(LedgerService::BalanceOverflow)

    expect(Account.find(user_id).balance).to eq(max_balance)
    expect(LedgerEntry.where(user_id: user_id).count).to eq(0)
    end

  end

  describe ".debit" do
    it "rolls back the balance when ledger creation fails" do
      user_id = "rollback_debit_user"

      described_class.credit(user_id: user_id, amount: 1_000)

      initial_balance = Account.find(user_id).balance
      initial_entries = LedgerEntry.where(user_id: user_id).count

      allow(LedgerEntry).to receive(:create!)
        .and_raise(ActiveRecord::RecordInvalid)

      expect {
        described_class.debit(user_id: user_id, amount: 400)
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(Account.find(user_id).balance).to eq(initial_balance)
      expect(LedgerEntry.where(user_id: user_id).count).to eq(initial_entries)
    end
  end
end
