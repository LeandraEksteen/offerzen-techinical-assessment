require "test_helper"

class ExportJobTest < ActiveJob::TestCase
  setup do
    @company = create_company
    @admin = create_admin(company: @company)
    @export = create_export(company: @company, admin: @admin)
  end

  # UT-16
  test "attaches a plain text/csv file through Active Storage and marks the export ready" do
    create_assessment(company: @company, status: "done", responses_json: { "score" => 70 })

    ExportJob.perform_now(@export)
    @export.reload

    assert @export.ready?
    assert_equal 1, @export.row_count
    assert @export.file.attached?
    assert_equal "text/csv", @export.file.content_type
    assert_match(/\.csv\z/, @export.file.filename.to_s)
    assert @export.file.download.start_with?("assessment_id,assessment_date,created_at,status,score,employee_id\n")
  end

  test "no Active Storage routes are drawn, so a signed blob link cannot bypass authorisation" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/rails/active_storage/blobs/redirect/anything/export.csv")
    end
  end

  # UT-12
  test "an error marks the export failed without retrying or leaking the message" do
    log = capture_log do
      with_failing_export("duplicate for jordan.sample@example.test private-note") do
        ExportJob.perform_now(@export)
      end
    end

    assert @export.reload.failed?
    assert_not @export.file.attached?
    assert_enqueued_jobs 0
    assert_log_clean log, "jordan.sample@example.test", "private-note"
    assert_includes log, "ExportJob failed export=#{@export.id} error=RuntimeError"
  end

  test "does nothing for an export that is not in progress" do
    @export.update!(state: :failed)

    ExportJob.perform_now(@export)

    assert @export.reload.failed?
    assert_not @export.file.attached?
  end

  # UT-15
  test "the purge job removes old files and marks the exports expired" do
    ExportJob.perform_now(@export)
    old = @export.reload
    assert old.file.attached?
    recent = create_export(company: @company, admin: @admin)
    ExportJob.perform_now(recent)

    travel 8.days
    fresh = create_export(company: @company, admin: @admin)
    ExpireExportsJob.perform_now

    assert old.reload.expired?
    assert_not old.file.attached?
    assert recent.reload.expired?
    assert fresh.reload.in_progress?
  end
end
