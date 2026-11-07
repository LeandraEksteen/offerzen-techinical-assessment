require "test_helper"

# TKT-9: the free-text BASELINE of the assessor status screen (Req 41). The
# validated dropdown replaces it in TKT-10 and these tests change with it.
class AssessmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @company = create_company(name: "Company A")
    @other_company = create_company(name: "Company B")
    @admin = create_admin(company: @company, email: "admin.a@example.test")
    @assessment = create_assessment(company: @company, status: "pending", responses_json: { "score" => 70, "comment" => "private words" })
  end

  teardown { Rails.cache = @original_cache }

  def save_status(value, assessment: @assessment)
    patch assessment_url(assessment), params: { assessment: { status: value } }
  end

  # UT-1
  test "an admin sees a free-text field holding the current status" do
    sign_in_as @admin

    get edit_assessment_url(@assessment)

    assert_response :success
    field = css_select("form input[type=text][name='assessment[status]']").first
    assert_equal "pending", field["value"]
    assert_select "input[type=submit][value=Save]"
  end

  # UT-2
  test "saving stores any text exactly as typed" do
    sign_in_as @admin

    [ "Comp", " Complete ", "whatever I like", "COMPLETED" ].each do |text|
      save_status text

      assert_redirected_to dashboard_url
      assert_equal text, @assessment.reload.status
    end
    follow_redirect!
    assert_select "[role=status]", text: "Status saved."
  end

  # UT-3
  test "an empty or blank value is stored as typed" do
    sign_in_as @admin

    save_status ""
    assert_equal "", @assessment.reload.status

    save_status "   "
    assert_equal "   ", @assessment.reload.status
  end

  # UT-4
  test "another company's assessment is not found and stays unchanged" do
    foreign = create_assessment(company: @other_company, status: "keep me")
    sign_in_as @admin

    get edit_assessment_url(foreign)
    assert_response :not_found

    save_status "hacked", assessment: foreign
    assert_response :not_found
    assert_equal "keep me", foreign.reload.status
  end

  # UT-5
  test "signed-out visitors are redirected to sign-in and change nothing" do
    get edit_assessment_url(@assessment)
    assert_redirected_to new_session_url

    save_status "hacked"
    assert_redirected_to new_session_url
    assert_equal "pending", @assessment.reload.status
  end

  # UT-6
  test "saving changes only the status and the update time" do
    before = Assessment.find(@assessment.id).attributes
    sign_in_as @admin

    travel 1.hour do
      save_status "Done"
    end

    after = @assessment.reload.attributes
    assert_equal({ "status" => [ "pending", "Done" ] }, before.except("updated_at").to_h { |key, value| [ key, [ value, after[key] ] ] }.reject { |_, (old, new)| old == new })
    assert_operator after["updated_at"], :>, before["updated_at"]
    assert_equal({ "score" => 70, "comment" => "private words" }, after["responses_json"])
  end

  # UT-7
  test "an unknown id is not found" do
    sign_in_as @admin

    get edit_assessment_url(0)
    assert_response :not_found
  end

  # UT-8
  test "a saved status shows in the dashboard's status filter at once" do
    sign_in_as @admin
    get dashboard_url
    assert_select "select[name=status] option", text: "Brand New", count: 0

    save_status "Brand New"
    get dashboard_url

    assert_select "select[name=status] option[value='brand new']"
  end

  # UT-9
  test "the form shows no employee email, never reads responses_json and logs no email" do
    sign_in_as @admin
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| queries << payload[:sql] }

    log = capture_log do
      get edit_assessment_url(@assessment)
      save_status "Done"
    end
    ActiveSupport::Notifications.unsubscribe(subscriber)

    assert_no_match(/employee@example\.test/, response.body)
    assert_no_match(/private words/, response.body)
    assessment_reads = queries.select { |sql| sql.include?('FROM "assessments"') }
    assert assessment_reads.any?
    assert assessment_reads.none? { |sql| sql.include?("responses_json") || sql.include?("employee_email") || sql.include?('"assessments".*') }, assessment_reads.inspect
    assert_log_clean log, "employee@example.test", "private words"
  end

  test "a request without the status parameter is a bad request and changes nothing" do
    sign_in_as @admin

    patch assessment_url(@assessment), params: {}

    assert_response :bad_request
    assert_equal "pending", @assessment.reload.status
  end
end
