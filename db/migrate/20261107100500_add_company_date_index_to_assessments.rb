# One composite index for the dashboard and the export date filter: the company
# plus the assessment date, so a page reads only that company's newest rows
# instead of scanning and sorting all of them.
#
# Built CONCURRENTLY so writes keep flowing while it builds (a plain CREATE INDEX
# blocks inserts and updates for as long as it runs). PostgreSQL does not allow
# that inside a transaction, hence disable_ddl_transaction!.
#
# A concurrent build that is interrupted or fails leaves an INVALID index behind.
# It slows writes and is never used, and Rails' if_not_exists would see it and skip
# rebuilding. So `up` clears an invalid leftover first, which makes a retry safe.
#
# Check it afterwards (operators):
#   SELECT c.relname, i.indisvalid, i.indisready
#   FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
#   WHERE i.indrelid = 'assessments'::regclass;
class AddCompanyDateIndexToAssessments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = "index_assessments_on_company_id_and_assessment_date".freeze

  def up
    drop_invalid_leftover
    add_index :assessments, %i[ company_id assessment_date ], name: INDEX_NAME, algorithm: :concurrently
  end

  def down
    remove_index :assessments, name: INDEX_NAME, algorithm: :concurrently
  end

  private

  def drop_invalid_leftover
    invalid = connection.select_value(<<~SQL)
      SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
      WHERE i.indrelid = 'assessments'::regclass AND c.relname = '#{INDEX_NAME}' AND NOT i.indisvalid
    SQL
    execute "DROP INDEX CONCURRENTLY IF EXISTS #{INDEX_NAME}" if invalid
  end
end
