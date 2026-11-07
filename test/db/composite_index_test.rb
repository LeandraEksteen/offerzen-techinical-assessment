require "test_helper"
require Rails.root.join("db/migrate/20261107100500_add_company_date_index_to_assessments")

# The migration builds an index CONCURRENTLY, which PostgreSQL forbids inside a
# transaction, so these tests run without the usual wrapping transaction and
# always put the index back.
class CompositeIndexTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  INDEX = AddCompanyDateIndexToAssessments::INDEX_NAME

  def connection
    ActiveRecord::Base.connection
  end

  def index_state
    connection.select_one(<<~SQL)
      SELECT i.indisvalid AS valid, i.indisready AS ready
      FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
      WHERE i.indrelid = 'assessments'::regclass AND c.relname = '#{INDEX}'
    SQL
  end

  def run_migration(direction)
    ActiveRecord::Migration.suppress_messages { AddCompanyDateIndexToAssessments.new.migrate(direction) }
  end

  teardown do
    run_migration(:up) if index_state.nil?
    if index_state && !index_state["valid"]
      connection.execute("DROP INDEX CONCURRENTLY IF EXISTS #{INDEX}")
      run_migration(:up)
    end
  end

  # UT-1
  test "the migration disables the DDL transaction so the concurrent build is allowed" do
    assert AddCompanyDateIndexToAssessments.disable_ddl_transaction
  end

  # UT-2
  test "the composite index exists on company and date and is valid and ready" do
    index = connection.indexes(:assessments).find { |candidate| candidate.name == INDEX }

    assert index, "expected #{INDEX} to exist"
    assert_equal [ "company_id", "assessment_date" ], index.columns
    assert_equal({ "valid" => true, "ready" => true }, index_state)
  end

  # UT-3
  test "the only secondary index on assessments is the composite one, with no status index" do
    names = connection.indexes(:assessments).map(&:name)

    assert_equal [ INDEX ], names
    assert_not connection.indexes(:assessments).flat_map(&:columns).include?("status")
  end

  # UT-4
  test "the migration rolls back and re-applies" do
    run_migration(:down)
    assert_nil index_state, "index should be gone after down"

    run_migration(:up)
    assert_equal({ "valid" => true, "ready" => true }, index_state)
  end

  # UT-5
  test "a leftover invalid index is dropped and rebuilt valid when the migration runs again" do
    connection.execute("UPDATE pg_index SET indisvalid = false WHERE indexrelid = '#{INDEX}'::regclass")
    assert_equal false, index_state["valid"]

    # What a retry does: the migration was never recorded, so `up` runs again.
    run_migration(:up)

    assert_equal({ "valid" => true, "ready" => true }, index_state)
  end
end
