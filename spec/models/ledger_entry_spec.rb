
require "rails_helper"

RSpec.describe LedgerEntry, type: :model do
  let(:user_id) { "immutable_test_user" }

  before do
    LedgerService.credit(user_id: user_id, amount: 1_000)
  end

  it "prevents modifying an existing ledger entry" do
    entry = LedgerEntry.find_by!(user_id: user_id)

    expect {
      ActiveRecord::Base.transaction(requires_new: true) do
        LedgerEntry.where(id: entry.id).update_all(amount: 500)
      end
    }.to raise_error(
      ActiveRecord::StatementInvalid,
      /Ledger entries are immutable/
    )

    expect(entry.reload.amount).to eq(1_000)
  end

  it "prevents deleting an existing ledger entry" do
    entry = LedgerEntry.find_by!(user_id: user_id)

    expect {
      ActiveRecord::Base.transaction(requires_new: true) do
        LedgerEntry.where(id: entry.id).delete_all
      end
    }.to raise_error(
      ActiveRecord::StatementInvalid,
      /Ledger entries are immutable/
    )

    expect(LedgerEntry.exists?(id: entry.id)).to be(true)
  end
end
