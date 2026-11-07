require "test_helper"

class StatusReportTest < ActiveSupport::TestCase
  setup do
    @company = create_company(name: "Acme")
  end

  def add(status, updated_at: nil, **attributes)
    assessment = create_assessment(company: @company, status: status, **attributes)
    assessment.update_columns(updated_at: updated_at) if updated_at
    assessment
  end

  def report(batch: StatusReport::BATCH, mapping: nil)
    output = StringIO.new
    StatusReport.new(output: output, batch: batch, mapping: mapping).call
    output.string
  end

  def row(text, value)
    text.lines.find { |line| line.include?("| #{value} |") }
  end

  def draft_mapping
    StatusMapping.new({ "version" => 0, "approved" => false, "mapping" => { "complete" => "completed", "done" => "completed", "pending" => "pending" } })
  end

  # UT-1
  test "prints one row per distinct stored value with a count and the latest updated_at" do
    add("Complete ", updated_at: Time.utc(2024, 1, 5, 10, 30))
    add("Complete ", updated_at: Time.utc(2025, 3, 9, 8, 15))
    add("complete", updated_at: Time.utc(2023, 2, 1))
    add("COMPLETE")
    add("pending")

    text = report

    assert_match(/5 assessments, 4 distinct stored values/, text)
    assert_match(/\A2 \| 2025-03-09 08:15 \| "Complete " \|/, row(text, '"Complete "'))
    assert_match(/\A1 \| 2023-02-01 00:00 \| "complete" \|/, row(text, '"complete"'))
    assert row(text, '"COMPLETE"')
    assert row(text, '"pending"')
  end

  # UT-2
  test "NULL, empty and blank-only values are separate labelled rows" do
    add(nil)
    add(nil)
    add("")
    add(" ")
    add("   ")

    text = report

    assert_match(/\A2 \|.*\| \(NULL\) \|/, row(text, "(NULL)"))
    assert_match(/\A1 \|.*\| \(empty\) \|/, row(text, "(empty)"))
    assert_match(/\(blank only, 1 character\)/, text)
    assert_match(/\(blank only, 3 characters\)/, text)
  end

  # UT-3
  test "is read only: no write or DDL statement runs and nothing changes" do
    add("Complete ", updated_at: Time.utc(2024, 1, 5), responses_json: { "score" => 80 })
    add(nil)
    before = Assessment.order(:id).pluck(:id, :status, :updated_at, :responses_json)
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| statements << payload[:sql] }

    report(mapping: draft_mapping)
    ActiveSupport::Notifications.unsubscribe(subscriber)

    assert statements.any?
    writes = statements.grep(/\A\s*(INSERT|UPDATE|DELETE|ALTER|CREATE|DROP|TRUNCATE)\b/i)
    assert_empty writes
    assert_equal before, Assessment.order(:id).pluck(:id, :status, :updated_at, :responses_json)
  end

  # UT-4
  test "batching by id gives the same output as one pass" do
    statuses = [ "done", "Done", nil, "", "complete", "done", "pending", "done", "n/a", "Complete " ]
    statuses.each_with_index { |status, index| add(status, updated_at: Time.utc(2024, 1, 1) + index.days) }

    assert_equal report, report(batch: 1)
    assert_equal report, report(batch: 3)
  end

  # UT-5
  test "free-looking text and emails are never printed and no ids or employee data appear" do
    add("please call alex.example@example.test about this one")
    add("this is a long note an assessor typed by mistake")
    add("x" * 80)
    add("mail me at pat@example.test")
    assessment = add("pending")
    assessment.update_columns(employee_email: "owner@example.test")

    text = report(mapping: draft_mapping)

    assert_no_match(/alex\.example|pat@example|owner@example|assessor typed|xxxxxxxx/, text)
    assert_equal 3, text.scan("REVIEW: looks like free text").size
    assert_match(/\[text, 80 characters\]/, text)
    assert_no_match(/employee@example\.test|Test Employee/, text)
    assert_no_match(/\b#{assessment.id}\b.*#{assessment.employee_id}/, text)
  end

  test "an email inside a short value is scrubbed" do
    add("a@b.example")

    assert_no_match(/a@b\.example/, report)
  end

  # UT-6
  test "with a mapping it shows where each value goes, rows per status and the unmapped rest" do
    add("Complete ")
    add("complete")
    add("done")
    add("pending")
    add("n/a")
    add("n/a")
    add(nil)

    text = report(mapping: draft_mapping)

    assert_match(/Mapping: db\/status_mapping\.yml version 0 \(DRAFT, not approved\)/, text)
    assert_match(/\| "Complete " \| completed \|/, text)
    assert_match(/\| "n\/a" \| \(unmapped\) \|/, text)
    assert_match(/^  completed\s+3 rows/, text)
    assert_match(/^  pending\s+1 rows/, text)
    assert_match(/^  archived\s+0 rows/, text)
    assert_match(/^  unmapped\s+3 rows in 2 distinct values/, text)
  end

  test "an approved mapping names who approved it" do
    mapping = StatusMapping.new({ "version" => 2, "approved" => true, "approved_by" => "Assessor lead", "approved_on" => "2026-12-01", "mapping" => { "done" => "completed" } })
    add("done")

    assert_match(/version 2 \(approved by Assessor lead on 2026-12-01\)/, report(mapping: mapping))
  end

  test "without a mapping file it says so by showing no mapping section" do
    add("done")

    text = report(mapping: nil)

    assert_no_match(/Mapping:/, text)
    assert_match(/\| "done" \| - \|/, text)
  end

  test "an empty table prints a clear zero report" do
    assert_match(/0 assessments, 0 distinct stored values/, report)
  end
end
