require "test_helper"

# Guards for the plan-only backfill (Req 42, 33): the status column is named in raw SQL
# in one place, so the later switch changes it once, and no application code changes a
# historical status.
class StatusGuardsTest < ActiveSupport::TestCase
  APP_FILES = Dir[Rails.root.join("{app,lib}/**/*.{rb,erb,rake}")].reject { |path| path.include?("/assets/") }

  # UT-9
  # A heuristic guard, not a parser: it looks for the column named inside a quoted SQL
  # string (btrim(status, lower(status, "status = ?", "status IS", "assessments.status").
  test "the raw SQL that names the status column exists only in StatusOptions::NORMALISED_SQL" do
    sql_on_status = /["`][^"`\n]*(\b(btrim|lower)\(\s*status|\bstatus\s+(=|IS|IN|<>|!=|LIKE)\s|\bstatus\s*(=|<>|!=)\s*\?|\b(assessments|a)\.status\b)/
    offenders = APP_FILES.filter_map do |path|
      next if path.end_with?("app/services/status_options.rb")

      code = File.read(path, encoding: "UTF-8").lines.reject { |line| line.strip.start_with?("#") }.join
      path.sub("#{Rails.root}/", "") if code.match?(sql_on_status)
    end

    assert_empty offenders, "raw SQL on the status column belongs in StatusOptions::NORMALISED_SQL"
    assert_includes File.read(Rails.root.join("app/services/status_options.rb")), "btrim(status"
    assert_equal "NULLIF(lower(btrim(status, E' \\t\\r\\n')), '')", StatusOptions::NORMALISED_SQL
  end

  # UT-10
  # Line level: a bulk writer is only a problem when the same line names assessments or
  # the status (ExportRequest bookkeeping and EXPLAIN statements are not historical data).
  test "no application code path updates historical statuses" do
    writers = /\b(update_all|update_columns?|update_attribute|insert_all!?|upsert_all|exec_update|exec_insert|connection\.execute)\b/
    allowed = [ "lib/assessment_seeder.rb" ] # writes test data in development with insert_all
    offenders = APP_FILES.flat_map do |path|
      relative = path.sub("#{Rails.root}/", "")
      next [] if allowed.include?(relative)

      File.read(path, encoding: "UTF-8").lines.each_with_index.filter_map do |line, index|
        "#{relative}:#{index + 1}" if !line.strip.start_with?("#") && line.match?(writers) && line.match?(/Assessment|assessments|status/)
      end
    end

    assert_empty offenders
  end

  test "the one allowed bulk writer is the seeder and it needs no validation bypass in production code" do
    assert_includes File.read(Rails.root.join("lib/assessment_seeder.rb")), "insert_all"
  end

  test "no migration changes data in the assessments table" do
    offenders = Dir[Rails.root.join("db/migrate/*.rb")].select do |path|
      File.read(path).match?(/UPDATE\s+assessments|update_all|Assessment\.|legacy_status|status_canonical/i)
    end

    assert_empty offenders.map { |path| File.basename(path) }
  end

  test "the report and the mapping contain no writes either" do
    [ "lib/status_report.rb", "lib/status_mapping.rb", "lib/tasks/statuses.rake" ].each do |path|
      code = File.readlines(Rails.root.join(path), chomp: true).reject { |line| line.strip.start_with?("#") }.join
      assert_no_match(/\.(save!?|update!?|create!?|destroy|delete|touch)\b|update_all|insert_all|execute/, code, path)
    end
  end
end
