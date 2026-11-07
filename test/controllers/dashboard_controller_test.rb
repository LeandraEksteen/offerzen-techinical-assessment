require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create_company(name: "Company A")
    @other_company = create_company(name: "Company B")
    @admin = create_admin(company: @company, email: "admin.a@example.test")
    @counter = 0
  end

  # Each assessment gets its own employee, so rows can be told apart.
  def add_assessment(company: @company, **attributes)
    @counter += 1
    employee = company.employees.create!(name: "Employee #{@counter}", email: "employee#{@counter}@example.test")
    Assessment.create!({ company: company, employee: employee, assessment_date: Date.current }.merge(attributes))
  end

  def table_rows
    css_select("tbody tr").map { |row| row.css("td").map { |cell| cell.text } }
  end

  def count_queries
    queries = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries += 1 unless payload[:cached] || %w[ SCHEMA TRANSACTION ].include?(payload[:name])
    end
    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  # UT-1
  test "lists only the signed-in admin's company with the five columns" do
    mine = add_assessment(status: "pending")
    add_assessment(company: @other_company, status: "secret-b-status")
    sign_in_as @admin

    get dashboard_url

    assert_response :success
    assert_equal [ "Employee email", "Employee id", "Assessment date", "Status", "Score" ], css_select("thead th").map(&:text)
    assert_equal 1, table_rows.size
    assert_equal [ mine.employee.email, mine.employee_id.to_s, mine.assessment_date.to_s, "pending" ], table_rows.first.first(4)
    assert_no_match(/secret-b-status/, response.body)
  end

  # UT-2
  test "signed-out visitors are redirected to sign-in" do
    get dashboard_url

    assert_redirected_to new_session_url
  end

  # UT-3
  test "the filters select exactly the rows the export selects" do
    add_assessment(assessment_date: "2025-01-10", status: "Complete")
    add_assessment(assessment_date: "2025-01-15", status: "complete ")
    add_assessment(assessment_date: "2025-02-01", status: nil)
    add_assessment(assessment_date: "2025-02-02", status: "")
    add_assessment(assessment_date: "2025-03-01", status: "n/a")
    sign_in_as @admin

    [ {}, { from: "2025-01-15", to: "2025-02-01" }, { from: "2025-02-02" }, { to: "2025-01-10" },
      { status: "complete" }, { status: StatusOptions::NONE }, { status: "n/a", from: "2025-01-01" } ].each do |filters|
      get dashboard_url, params: filters
      dashboard_ids = table_rows.map { |row| row[1] }.sort

      export = create_export(company: @company, admin: @admin, date_from: filters[:from], date_to: filters[:to],
                             status_filter: filters[:status], state: :failed)
      export_ids = export_csv(export)["employee_id"].sort

      assert_equal export_ids, dashboard_ids, "dashboard and export disagree for #{filters}"
    end
  end

  # UT-4
  test "the status select offers the company's own grouped statuses" do
    add_assessment(status: "Complete")
    add_assessment(status: "complete ")
    add_assessment(status: nil)
    add_assessment(company: @other_company, status: "secret-b-status")
    sign_in_as @admin

    get dashboard_url

    assert_equal [ "All", "complete", "(no status)" ], css_select("select[name=status] option").map(&:text)
  end

  # UT-5
  test "a start date after the end date gives 422, a message and no table" do
    add_assessment
    sign_in_as @admin

    get dashboard_url, params: { from: "2025-02-01", to: "2025-01-01" }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", /Start date is after the end date/
    assert_select "table", 0
  end

  # UT-6
  test "rows are ordered by assessment date descending, then id descending" do
    older = add_assessment(assessment_date: "2025-01-01")
    first_of_day = add_assessment(assessment_date: "2025-06-01")
    second_of_day = add_assessment(assessment_date: "2025-06-01")
    sign_in_as @admin

    get dashboard_url

    assert_equal [ second_of_day, first_of_day, older ].map { |a| a.employee_id.to_s }, table_rows.map { |row| row[1] }
  end

  # UT-7
  test "every score shape renders without an error, shown as stored and blank when absent" do
    shapes = [ { "score" => 85 }, { "score" => "85%" }, { "score" => 0.85 }, { "score" => 150 }, { "score" => nil },
               { "comments" => "no score" }, [ 85 ], { "score" => 85 }.to_json, nil ]
    shapes.each { |json| add_assessment(responses_json: json) }
    sign_in_as @admin

    get dashboard_url

    assert_response :success
    scores = table_rows.map { |row| row[4] }
    assert_equal [ "85", "85%", "0.85", "150", "", "", "", "", "" ].sort, scores.sort
  end

  test "every seeded status and date filter combination returns 200" do
    [ "Complete", "pending", nil, "", "n/a", "comp" ].each_with_index { |status, i| add_assessment(status: status, assessment_date: Date.new(2025, 1, 1) + i) }
    sign_in_as @admin

    [ { from: "2025-01-02" }, { to: "2025-01-04" }, { status: "complete" }, { status: "pending", from: "2025-01-01", to: "2025-12-31" },
      { status: StatusOptions::NONE }, { status: "n/a" }, { status: "comp", to: "2025-01-06" } ].each do |filters|
      get dashboard_url, params: filters
      assert_response :success, "filters #{filters}"
    end
  end

  # UT-8
  test "the baseline reads each employee separately, so queries grow with the rows" do
    sign_in_as @admin
    3.times { add_assessment }
    few = count_queries { get dashboard_url }
    3.times { add_assessment }
    many = count_queries { get dashboard_url }

    assert_operator many - few, :>=, 3, "baseline should do one extra query per extra row (an N+1), got #{few} then #{many}"
  end

  # UT-9
  test "loading the dashboard with filters leaves no emails, response content or raw scores in the log" do
    add_assessment(employee_email: "private.person@example.test", status: "done",
                   responses_json: { "score" => 61.8437, "comments" => "private-comment-text" })
    sign_in_as @admin

    log = capture_log do
      get dashboard_url, params: { from: "2020-01-01", status: "done" }
      get dashboard_url, params: { from: "2025-02-01", to: "2025-01-01" }
    end

    assert_log_clean log, "private.person@example.test", "employee1@example.test", "admin.a@example.test", "private-comment-text", "61.8437"
    assert_includes log, "Processing by DashboardController#show"
  end
end
