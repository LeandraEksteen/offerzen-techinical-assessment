require "test_helper"

class AssessmentCsvExportTest < ActiveSupport::TestCase
  setup do
    @company = create_company(name: "Acme")
    @admin = create_admin(company: @company)
  end

  # UT-3
  test "the header is exactly the six allowed columns and no personal data appears" do
    create_assessment(company: @company, employee_email: "private.person@example.test", status: "done",
                      responses_json: { "score" => 80, "comments" => "private-comment-text", "answers" => [ { "q" => "q1", "value" => 5 } ] })

    io = StringIO.new
    AssessmentCsvExport.new(create_export(company: @company, admin: @admin)).write_to(io)

    assert_equal "assessment_id,assessment_date,created_at,status,score,employee_id", io.string.lines.first.strip
    assert_equal 2, io.string.lines.size
    assert_log_clean io.string, "private.person@example.test", "private-comment-text", "answers", "comments", "Test Employee", "employee@example.test"
  end

  # UT-4
  test "status cells that could run as formulas are neutralised" do
    [ "=SUM(1)", "+1", "-1", "@x", "done" ].each { |status| create_assessment(company: @company, status: status) }

    csv = export_csv(create_export(company: @company, admin: @admin))

    assert_equal [ "'=SUM(1)", "'+1", "'-1", "'@x", "done" ], csv["status"]
  end

  # UT-5
  test "refuses a column list that contains personal data" do
    assert_nothing_raised { AssessmentCsvExport.ensure_no_pii!(AssessmentCsvExport::COLUMNS) }
    error = assert_raises(RuntimeError) { AssessmentCsvExport.ensure_no_pii!(%w[ status employee_email ]) }

    assert_match(/employee_email/, error.message)
    assert_raises(RuntimeError) { AssessmentCsvExport.ensure_no_pii!(%w[ responses_json ]) }
  end

  # UT-6 (TKT-3) / UT-10 (TKT-8): the score is whatever ScoreReader reads, blank when none
  test "the score cell is the reader's value, blank when there is no valid score" do
    shapes = [ { "score" => 85 }, { "score" => 84.5 }, { "score" => "85" }, { "score" => "85%" }, { "score" => nil },
               { "comments" => "no score here" }, [ 85 ], { "score" => 85 }.to_json, nil, { "score" => { "nested" => 1 } },
               { "score" => 0.85 }, { "score" => 150 }, { "assessment_score" => "70" } ]
    shapes.each { |json| create_assessment(company: @company, responses_json: json) }

    csv = export_csv(create_export(company: @company, admin: @admin))

    assert_equal [ "85", "85", "85", "85", "", "", "", "", "", "", "", "", "70" ], csv["score"].map(&:to_s)
  end

  # UT-7
  test "the date range is inclusive and either end is optional" do
    dates = %w[ 2026-01-01 2026-01-15 2026-01-31 2026-02-10 ]
    dates.each { |date| create_assessment(company: @company, assessment_date: date) }

    both = export_csv(create_export(company: @company, admin: @admin, date_from: "2026-01-15", date_to: "2026-01-31"))
    only_from = export_csv(create_export(company: @company, admin: @admin, date_from: "2026-01-31", state: :failed))
    only_to = export_csv(create_export(company: @company, admin: @admin, date_to: "2026-01-01", state: :failed))

    assert_equal %w[ 2026-01-15 2026-01-31 ], both["assessment_date"]
    assert_equal %w[ 2026-01-31 2026-02-10 ], only_from["assessment_date"]
    assert_equal %w[ 2026-01-01 ], only_to["assessment_date"]
  end

  test "status variants match one filter value and no-status matches nil, empty and blank" do
    [ "Complete", "complete ", "COMPLETE", "comp", nil, "", "   ", "n/a", "pending" ].each do |status|
      create_assessment(company: @company, status: status)
    end

    complete = export_csv(create_export(company: @company, admin: @admin, status_filter: "complete", state: :failed))
    none = export_csv(create_export(company: @company, admin: @admin, status_filter: StatusOptions::NONE, state: :failed))
    not_applicable = export_csv(create_export(company: @company, admin: @admin, status_filter: "n/a", state: :failed))

    assert_equal 3, complete.size
    assert_equal 3, none.size
    assert_equal [ "n/a" ], not_applicable["status"]
  end

  test "a company never sees another company's rows" do
    other = create_company(name: "Other")
    create_assessment(company: @company)
    create_assessment(company: other)

    csv = export_csv(create_export(company: @company, admin: @admin))

    assert_equal 1, csv.size
  end

  # UT-11
  test "exports every row across several batches in id order" do
    ids = Array.new(10) { create_assessment(company: @company).id }
    queries = 0
    counter = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries += 1 if payload[:sql].include?('FROM "assessments"') && payload[:sql].include?("LIMIT")
    end

    csv = export_csv(create_export(company: @company, admin: @admin), batch_size: 3)
    ActiveSupport::Notifications.unsubscribe(counter)

    assert_equal ids.map(&:to_s), csv["assessment_id"]
    assert_operator queries, :>=, 4
  end
end
