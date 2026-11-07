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

  # UT-1 (TKT-6): replaces the baseline test that asserted one query per row.
  test "the query count does not grow with the number of rows" do
    sign_in_as @admin
    counts = {}
    [ 3, 20, 50 ].each do |rows|
      Assessment.where(company: @company).delete_all
      add_assessments(rows)
      counts[rows] = count_queries { get dashboard_url }
      assert_equal rows, table_rows.size
    end

    assert_equal 1, counts.values.uniq.size, "queries per page should be constant, got #{counts}"
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

  # --- pagination (TKT-5) ---

  def add_assessments(count, **attributes)
    Array.new(count) { add_assessment(**attributes) }
  end

  def page_links
    css_select("nav[aria-label=Pages] a").map { |link| link.text }
  end

  # UT-1
  test "pages hold 50 rows: 120 rows give 50, 50 and 20" do
    add_assessments(120)
    sign_in_as @admin

    sizes = [ 1, 2, 3 ].map do |page|
      get dashboard_url, params: { page: page }
      table_rows.size
    end

    assert_equal [ 50, 50, 20 ], sizes
  end

  # UT-2
  test "exactly 50 rows has no Next link and 51 rows has one but shows 50" do
    add_assessments(50)
    sign_in_as @admin
    get dashboard_url
    assert_equal 50, table_rows.size
    assert_not_includes page_links, "Next"

    add_assessment
    get dashboard_url
    assert_equal 50, table_rows.size
    assert_includes page_links, "Next"
  end

  # UT-3
  test "Previous shows only from page 2, Next only when more rows exist, and no total count" do
    add_assessments(120)
    sign_in_as @admin

    get dashboard_url
    assert_equal [ "Next" ], page_links
    get dashboard_url, params: { page: 2 }
    assert_equal [ "Previous", "Next" ], page_links
    get dashboard_url, params: { page: 3 }
    assert_equal [ "Previous", "First page" ], page_links
    assert_no_match(/\bof \d+\b|total/i, response.body)
    assert_match(/Rows 101 to 120/, response.body)
  end

  # UT-4
  test "bad page values show page 1 with status 200" do
    first = add_assessments(60).last
    sign_in_as @admin

    [ "abc", "-1", "0", "", "1.5", "1e3", " 2", "2 ", "1000001", "100000000000000000000" ].each do |value|
      get dashboard_url, params: { page: value }
      assert_response :success, "page=#{value.inspect}"
      assert_equal 50, table_rows.size, "page=#{value.inspect}"
      assert_equal first.employee_id.to_s, table_rows.first[1], "page=#{value.inspect} should be page 1"
    end
    get "/dashboard?page[]=2"
    assert_response :success
    assert_equal first.employee_id.to_s, table_rows.first[1]
  end

  # UT-5
  test "a page past the last shows an empty page with a way back" do
    add_assessments(60)
    sign_in_as @admin

    get dashboard_url, params: { page: 9 }

    assert_response :success
    assert_equal 0, table_rows.size
    assert_match(/No assessments on this page/, response.body)
    assert_equal [ "Previous", "First page" ], page_links
  end

  test "a company with no rows shows a plain message" do
    sign_in_as @admin

    get dashboard_url

    assert_response :success
    assert_match(/No assessments\./, response.body)
    assert_equal [], page_links
  end

  # UT-6
  test "with every row on one date the pages together hold each row exactly once, newest id first" do
    ids = add_assessments(120, assessment_date: "2025-06-01").map(&:employee_id)
    sign_in_as @admin

    seen = [ 1, 2, 3 ].flat_map do |page|
      get dashboard_url, params: { page: page }
      table_rows.map { |row| row[1].to_i }
    end

    assert_equal ids.sort.reverse, seen
    assert_equal seen.uniq, seen
  end

  # UT-7
  test "page links keep the filters and copy no other parameter" do
    add_assessments(120, status: "pending", assessment_date: "2025-03-01")
    sign_in_as @admin

    get dashboard_url, params: { from: "2025-01-01", to: "2025-12-31", status: "pending", page: 2, company_id: @other_company.id, secret: "x" }

    hrefs = css_select("nav[aria-label=Pages] a").map { |link| link["href"] }
    assert_equal 2, hrefs.size
    hrefs.each do |href|
      query = Rack::Utils.parse_query(URI.parse(href).query)
      assert_equal [ "from", "page", "status", "to" ], query.keys.sort
      assert_equal "pending", query["status"]
    end
    assert_equal [ "1", "3" ], hrefs.map { |href| Rack::Utils.parse_query(URI.parse(href).query)["page"] }.sort
  end

  # UT-8
  test "page 1 shows exactly the first 50 rows of the full ordered list" do
    add_assessments(75).each_with_index { |a, i| a.update_columns(assessment_date: Date.new(2025, 1, 1) + (i % 5)) }
    sign_in_as @admin

    get dashboard_url

    expected = @company.assessments.order(assessment_date: :desc, id: :desc).limit(50).map { |a| a.employee_id.to_s }
    assert_equal expected, table_rows.map { |row| row[1] }
  end

  # UT-2 (TKT-6)
  test "a page of 50 rows runs at most 8 SQL queries" do
    add_assessments(120)
    sign_in_as @admin

    queries = count_queries { get dashboard_url }

    assert_operator queries, :<=, 8, "page 1 ran #{queries} queries"
  end

  # UT-3 (TKT-6)
  test "the employee query selects only id and email" do
    add_assessments(5)
    sign_in_as @admin
    employee_sql = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      employee_sql << payload[:sql] if payload[:sql].include?('FROM "employees"')
    end

    get dashboard_url
    ActiveSupport::Notifications.unsubscribe(subscriber)

    assert_equal 1, employee_sql.size, "expected one employees query, got #{employee_sql.size}"
    assert_match(/SELECT "employees"\."id", "employees"\."email" FROM "employees"/, employee_sql.first)
    assert_no_match(/"employees"\."name"/, employee_sql.first)
  end

  test "employees loaded for the list carry no attribute beyond id and email" do
    assessment = add_assessment
    loaded = Assessment.where(id: assessment.id).preload(:employee_for_listing).first.employee_for_listing

    assert_equal [ "email", "id" ], loaded.attributes.keys.sort
  end

  # UT-6 (TKT-6)
  test "reading an employee attribute that was not loaded raises instead of running another query" do
    assessment = add_assessment
    loaded = Assessment.where(id: assessment.id).preload(:employee_for_listing).first.employee_for_listing

    assert_raises(ActiveModel::MissingAttributeError) { loaded.name }
  end

  # UT-4 (TKT-6)
  test "the page shows the same emails, rows and order as reading each employee separately" do
    add_assessments(30).each_with_index { |a, i| a.update_columns(assessment_date: Date.new(2025, 1, 1) + (i % 4)) }
    sign_in_as @admin

    get dashboard_url

    expected = @company.assessments.order(assessment_date: :desc, id: :desc).limit(50).map { |a| [ a.employee.email, a.employee_id.to_s ] }
    assert_equal expected, table_rows.map { |row| [ row[0], row[1] ] }
  end

  # UT-5 (TKT-6)
  test "several assessments sharing one employee each show that employee's email" do
    employee = @company.employees.create!(name: "Shared Person", email: "shared.person@example.test")
    3.times { |n| Assessment.create!(company: @company, employee: employee, assessment_date: Date.new(2025, 1, 1) + n) }
    other = add_assessment(assessment_date: "2025-06-01")
    sign_in_as @admin

    get dashboard_url

    assert_equal [ other.employee.email ] + Array.new(3, "shared.person@example.test"), table_rows.map { |row| row[0] }
  end

  # UT-10
  test "invalid filters still return 422 with no table and no paging links" do
    add_assessments(60)
    sign_in_as @admin

    get dashboard_url, params: { from: "2025-02-01", to: "2025-01-01", page: 2 }

    assert_response :unprocessable_entity
    assert_select "table", 0
    assert_equal [], page_links
  end
end
