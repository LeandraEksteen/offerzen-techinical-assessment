require "test_helper"

class ExportsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @company = create_company(name: "Company A")
    @other_company = create_company(name: "Company B")
    @admin = create_admin(company: @company, email: "admin.a@example.test")
    @other_admin = create_admin(company: @other_company, email: "admin.b@example.test")
  end

  # UT-1
  test "an admin exports only their own company, whatever company_id is sent" do
    mine = create_assessment(company: @company)
    create_assessment(company: @other_company)
    sign_in_as @admin

    perform_enqueued_jobs { post exports_url, params: { company_id: @other_company.id } }

    export = ExportRequest.last
    assert_equal @company, export.company
    csv = CSV.parse(export.file.download, headers: true)
    assert_equal [ mine.id.to_s ], csv["assessment_id"]
  end

  # UT-2
  test "another company's admin gets a 404 for the download, and signed-out users are redirected" do
    create_assessment(company: @company)
    sign_in_as @admin
    perform_enqueued_jobs { post exports_url }
    export = ExportRequest.last
    get export_url(export)
    assert_response :success
    delete session_url

    get export_url(export)
    assert_redirected_to new_session_url

    sign_in_as @other_admin
    get export_url(export)
    assert_response :not_found
  end

  # UT-8
  test "invalid input returns 422 with a plain message and creates nothing" do
    sign_in_as @admin
    create_assessment(company: @company, status: "pending")

    post exports_url, params: { from: "not-a-date" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /Start date is not a valid date/

    post exports_url, params: { from: "2026-02-01", to: "2026-01-01" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /Start date is after the end date/

    post exports_url, params: { status: "never-heard-of-it" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /not one of your statuses/

    assert_equal 0, ExportRequest.count
    assert_no_enqueued_jobs
  end

  test "a blank status means all and no-status is a valid filter" do
    create_assessment(company: @company, status: nil)
    sign_in_as @admin

    post exports_url, params: { status: "", from: "", to: "" }
    assert_redirected_to exports_url
    delete session_url
    ExportRequest.update_all(state: "ready")
    sign_in_as @admin
    post exports_url, params: { status: StatusOptions::NONE }

    assert_redirected_to exports_url
    assert_equal StatusOptions::NONE, ExportRequest.last.status_filter
  end

  # UT-10
  test "starting an export shows it in progress, then ready with a download link" do
    create_assessment(company: @company, responses_json: { "score" => 90 })
    sign_in_as @admin
    get exports_url
    assert_response :success

    assert_enqueued_with(job: ExportJob) { post exports_url, params: { from: "2020-01-01" } }
    assert_redirected_to exports_url
    follow_redirect!
    assert_select "[role=status]", /Export started/
    assert_select "[role=status]", /Refresh this page/
    assert_select "td", /In progress/
    assert_select "a", text: "Download CSV", count: 0

    perform_enqueued_jobs
    get exports_url
    assert_select "td", /Ready/
    assert_select "a[href=?]", export_path(ExportRequest.last), text: "Download CSV"
    assert_select "[role=status]", text: /Refresh this page/, count: 0

    get export_url(ExportRequest.last)
    assert_response :success
    assert_equal "text/csv", response.media_type
  end

  test "the history shows the 20 most recent exports of the own company only" do
    22.times { |n| create_export(company: @company, admin: @admin, state: :ready, row_count: 1000 + n) }
    create_export(company: @other_company, admin: @other_admin, state: :ready, row_count: 777_777)
    sign_in_as @admin

    get exports_url

    assert_select "tbody tr", 20
    assert_no_match(/777777/, response.body)
    assert_match(/1021/, response.body)
    assert_no_match(/>1000</, response.body)
  end

  test "the status select lists only the company's own statuses" do
    create_assessment(company: @company, status: "pending")
    create_assessment(company: @other_company, status: "secret-b-status")
    sign_in_as @admin

    get exports_url

    assert_select "select[name=status] option", text: "pending"
    assert_select "select[name=status] option", text: "secret-b-status", count: 0
  end

  # UT-13
  test "a second export while one is in progress is refused" do
    sign_in_as @admin
    post exports_url
    assert_redirected_to exports_url

    assert_no_difference "ExportRequest.count" do
      post exports_url
    end

    assert_response :unprocessable_entity
    assert_select "[role=alert]", /already in progress/
  end

  # UT-14
  test "after 30 minutes an in-progress export shows as failed and a new one can start" do
    sign_in_as @admin
    post exports_url
    travel 31.minutes

    get exports_url
    assert_select "td", /Failed/
    assert_select "td", /Export failed, please try again/

    assert_difference "ExportRequest.count", 1 do
      post exports_url
    end
  end

  # UT-15
  test "an expired export cannot be downloaded" do
    create_assessment(company: @company)
    sign_in_as @admin
    perform_enqueued_jobs { post exports_url }
    export = ExportRequest.last
    travel 8.days
    sign_in_as @admin

    get exports_url
    assert_select "td", /Expired/
    get export_url(export)

    assert_response :not_found
  end

  test "a failed or in-progress export cannot be downloaded" do
    sign_in_as @admin
    post exports_url
    get export_url(ExportRequest.last)

    assert_response :not_found
  end

  # UT-18
  test "the page wires the Stimulus controller" do
    sign_in_as @admin

    get exports_url

    assert_select "form[data-controller=export-form]"
    assert_select "[data-export-form-target=button]"
    assert_select "[data-export-form-target=message][hidden]"
  end

  test "signed-out users are redirected from every export page" do
    get exports_url
    assert_redirected_to new_session_url

    post exports_url
    assert_redirected_to new_session_url
  end
end
