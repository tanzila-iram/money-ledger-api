
class EnforceLedgerEntryImmutability < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION prevent_ledger_entry_changes()
      RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'Ledger entries are immutable';
      END;
      $$ LANGUAGE plpgsql;
    SQL

    execute <<~SQL
      CREATE TRIGGER ledger_entries_immutable
      BEFORE UPDATE OR DELETE ON ledger_entries
      FOR EACH ROW
      EXECUTE FUNCTION prevent_ledger_entry_changes();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS ledger_entries_immutable ON ledger_entries;
    SQL

    execute <<~SQL
      DROP FUNCTION IF EXISTS prevent_ledger_entry_changes();
    SQL
  end
end
