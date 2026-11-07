require "test_helper"

# The dashboard, the export and the report all read scores through ScoreReader.
class ScoreReaderPagesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  SHAPES = [ { "score" => 85 }, { "score" => 84.5 }, { "score" => 84.99999 }, { "score" => "85" }, { "score" => "85%" },
             { "score" => "84,5" }, { "assessment_score" => 70 }, { "total_score" => "60%" }, { "overall_score" => 55.5 },
             { "score" => 90, "assessment_score" => 60 }, { "score" => 0.85 }, { "score" => 150 }, { "score" => -5 },
             { "score" => "N/A" }, { "score" => "" }, { "score" => nil }, { "comments" => "no score" }, { "score" => "1,234" },
             "{\"score\":85}", [ 85 ], nil, { "score" => true }, { "score" => { "nested" => 1 } } ].freeze

  setup do
    @company = create_company(name: "Company A")
    @admin = create_admin(company: @company, email: "admin.a@example.test")
    @counter = 0
  end

  def add_assessment(**attributes)
    @counter += 1
    employee = @company.employees.create!(name: "Employee #{@counter}", email: "employee#{@counter}@example.test")
    Assessment.create!({ company: @company, employee: employee, assessment_date: Date.current }.merge(attributes))
  end

  def dashboard_scores
    css_select("tbody tr").to_h { |row| cells = row.css("td").map(&:text); [ cells[1], cells[4] ] }
  end

  def sql_during
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| statements << payload[:sql] }
    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  # UT-10
  test "the export's score cell agrees with the dashboard for every shape, and unavailable is blank" do
    SHAPES.each { |json| add_assessment(responses_json: json) }
    sign_in_as @admin

    get dashboard_url
    on_screen = dashboard_scores
    export = create_export(company: @company, admin: @admin)
    in_csv = export_csv(export).to_h { |row| [ row["employee_id"], row["score"] ] }

    assert_equal SHAPES.size, on_screen.size
    on_screen.each do |employee_id, shown|
      expected = shown == "Score not available" ? nil : shown
      message = "employee #{employee_id}: dashboard #{shown.inspect}, csv #{in_csv[employee_id].inspect}"
      expected.nil? ? assert_nil(in_csv[employee_id], message) : assert_equal(expected, in_csv[employee_id], message)
    end
    assert_operator on_screen.values.count("Score not available"), :>, 5
    assert_operator in_csv.values.compact.size, :>, 5
  end

  # UT-11
  test "a reader that raises on a row is rescued: 200, Score not available, and only the class and id are logged" do
    assessment = add_assessment(responses_json: { "score" => 61.8437, "comments" => "private-comment-text" })
    sign_in_as @admin
    original = ScoreReader.method(:read)
    ScoreReader.define_singleton_method(:read) { |*| raise "boom with 61.8437 and private-comment-text" }

    log = capture_log { get dashboard_url }

    assert_response :success
    assert_equal [ "Score not available" ], css_select("tbody tr").map { |row| row.css("td")[4].text }
    assert_includes log, "score display failed assessment=#{assessment.id} error=RuntimeError"
    assert_log_clean log, "61.8437", "private-comment-text", "boom"
  ensure
    ScoreReader.define_singleton_method(:read, original)
  end

  # UT-12
  test "responses_json is unchanged after the dashboard, the export and the report" do
    SHAPES.each { |json| add_assessment(responses_json: json) }
    sign_in_as @admin
    before = Assessment.order(:id).pluck(:id, :responses_json, :updated_at)

    get dashboard_url
    export_csv(create_export(company: @company, admin: @admin))
    ScoreReport.new(output: StringIO.new, batch: 5).call

    assert_equal before, Assessment.order(:id).pluck(:id, :responses_json, :updated_at)
  end

  # UT-14
  test "loading the dashboard leaves no emails, response content or raw scores in the log" do
    add_assessment(responses_json: { "score" => "61,8437%", "comments" => "private-comment-text" })
    add_assessment(responses_json: { "score" => 33.337, "answers" => [ { "q" => "q1" } ] })
    sign_in_as @admin

    log = capture_log { get dashboard_url, params: { from: "2020-01-01" } }

    assert_log_clean log, "employee1@example.test", "admin.a@example.test", "private-comment-text", "61,8437", "33.337", "answers"
    assert_includes log, "Processing by DashboardController#show"
  end

  # UT-15
  test "neither the dashboard nor the export reads the whole responses_json" do
    add_assessment(responses_json: { "score" => 80, "comments" => "private-comment-text" })
    sign_in_as @admin

    page_sql = sql_during { get dashboard_url }.grep(/FROM "assessments"/).reject { |sql| sql.include?("DISTINCT") }
    export_sql = sql_during { export_csv(create_export(company: @company, admin: @admin)) }.grep(/FROM "assessments"/).reject { |sql| sql.include?("DISTINCT") }

    [ page_sql, export_sql ].each do |statements|
      assert_not_empty statements
      statements.each do |sql|
        assert_no_match(/"assessments"\.\*/, sql)
        assert_no_match(/"assessments"\."responses_json"/, sql)
        assert_match(/responses_json->'score'/, sql)
      end
    end
  end
end
