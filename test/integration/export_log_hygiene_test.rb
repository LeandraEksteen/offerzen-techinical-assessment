require "test_helper"

class ExportLogHygieneTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @company = create_company
    @admin = create_admin(company: @company, email: "jordan.sample@example.test")
    create_assessment(company: @company, employee_email: "private.person@example.test", status: "done",
                      responses_json: { "score" => 61.8437, "comments" => "private-comment-text" })
  end

  # UT-17
  test "a successful export leaves no emails, response content or raw scores in the log" do
    log = capture_log do
      sign_in_as @admin
      perform_enqueued_jobs { post exports_url, params: { from: "2020-01-01", status: "done" } }
      get exports_url
      get export_url(ExportRequest.last)
    end

    assert_log_clean log, "jordan.sample@example.test", "private.person@example.test", "private-comment-text", "61.8437", TEST_PASSWORD
    assert_includes log, "Processing by ExportsController#create"
    assert_includes log, "ExportJob"
  end

  test "a failing export leaves no data in the log" do
    log = capture_log do
      sign_in_as @admin
      with_failing_export("boom for private.person@example.test with private-comment-text 61.8437") do
        perform_enqueued_jobs { post exports_url }
      end
      get exports_url
    end

    assert ExportRequest.last.failed?
    assert_log_clean log, "jordan.sample@example.test", "private.person@example.test", "private-comment-text", "61.8437"
    assert_includes log, "ExportJob failed"
  end
end
