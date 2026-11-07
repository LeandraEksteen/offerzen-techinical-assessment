require "test_helper"

# The assessor status screen, VALIDATED version (Req 41): a dropdown of the five
# statuses. The free-text baseline (TKT-9) is in git history.
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

  def with_cutover(date)
    original = Rails.configuration.x.status_cutover_date
    Rails.configuration.x.status_cutover_date = date
    yield
  ensure
    Rails.configuration.x.status_cutover_date = original
  end

  # UT-10
  test "the screen offers the five statuses in a select and no text field" do
    sign_in_as @admin

    get edit_assessment_url(@assessment)

    assert_response :success
    assert_select "form input[type=text]", count: 0
    assert_equal Assessment::STATUSES, css_select("select[name='assessment[status]'] option").map { |option| option["value"] }.reject(&:empty?)
    assert_select "select[required]"
    assert_select "option[selected][value=pending]"
    assert_no_match(/not a standard status/, response.body)
  end

  test "a legacy value is shown as a note, not as a choice, and nothing is preselected" do
    legacy = create_assessment(company: @company, status: "Complete ")
    sign_in_as @admin

    get edit_assessment_url(legacy)

    assert_match(/Current value "Complete " is not a standard status/, response.body)
    assert_select "select option[selected]", count: 0
    assert_select "select option[value='Complete ']", count: 0
    assert_equal "", css_select("select option").first["value"]
  end

  test "a row with no status asks for a choice too" do
    blank = create_assessment(company: @company, status: nil)
    sign_in_as @admin

    get edit_assessment_url(blank)

    assert_match(/No standard status is set/, response.body)
  end

  # UT-11
  test "choosing a status saves it and goes back to the dashboard" do
    sign_in_as @admin

    save_status "needs_follow_up"

    assert_redirected_to dashboard_url
    assert_equal "needs_follow_up", @assessment.reload.status
    follow_redirect!
    assert_select "[role=status]", text: "Status saved."
  end

  test "a legacy row can be corrected to a canonical status" do
    legacy = create_assessment(company: @company, status: "Complete ")
    sign_in_as @admin

    save_status "completed", assessment: legacy

    assert_equal "completed", legacy.reload.status
  end

  # UT-12
  test "empty, missing and non-canonical values are refused before and after the cut-over date" do
    [ nil, Date.current + 30, Date.current - 30 ].each do |cutover|
      with_cutover(cutover) do
        sign_in_as @admin
        [ "", " ", "Complete", "completed ", "done", "PENDING" ].each do |value|
          save_status value

          assert_response :unprocessable_entity
          assert_select "[role=alert]", text: "Choose one of the listed statuses."
          assert_equal "pending", @assessment.reload.status
        end

        patch assessment_url(@assessment), params: {}
        assert_response :bad_request
        assert_equal "pending", @assessment.reload.status
      end
    end
  end

  # UT-13
  test "another company's assessment is not found and stays unchanged" do
    foreign = create_assessment(company: @other_company, status: "archived")
    sign_in_as @admin

    get edit_assessment_url(foreign)
    assert_response :not_found

    save_status "pending", assessment: foreign
    assert_response :not_found
    assert_equal "archived", foreign.reload.status
  end

  test "signed-out visitors are redirected to sign-in and change nothing" do
    get edit_assessment_url(@assessment)
    assert_redirected_to new_session_url

    save_status "archived"
    assert_redirected_to new_session_url
    assert_equal "pending", @assessment.reload.status
  end

  test "an unknown id is not found" do
    sign_in_as @admin

    get edit_assessment_url(0)
    assert_response :not_found
  end

  test "saving changes only the status and the update time" do
    sign_in_as @admin
    before = Assessment.find(@assessment.id).attributes

    travel 1.hour do
      save_status "archived"
    end

    after = @assessment.reload.attributes
    changed = after.keys.reject { |key| before[key] == after[key] }
    assert_equal %w[ status updated_at ], changed.sort
    assert_equal({ "score" => 70, "comment" => "private words" }, after["responses_json"])
  end

  # UT-11
  test "a saved status shows in the dashboard's status filter at once" do
    sign_in_as @admin
    get dashboard_url
    assert_select "select[name=status] option[value=archived]", count: 0

    save_status "archived"
    get dashboard_url

    assert_select "select[name=status] option[value=archived]"
  end

  test "the form shows no employee email, never reads responses_json and logs no email" do
    sign_in_as @admin
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| queries << payload[:sql] }

    log = capture_log do
      get edit_assessment_url(@assessment)
      save_status "archived"
    end
    ActiveSupport::Notifications.unsubscribe(subscriber)

    assert_no_match(/employee@example\.test/, response.body)
    assert_no_match(/private words/, response.body)
    assessment_reads = queries.select { |sql| sql.include?('FROM "assessments"') }
    assert assessment_reads.any?
    assert assessment_reads.none? { |sql| sql.include?("responses_json") || sql.include?("employee_email") || sql.include?('"assessments".*') }, assessment_reads.inspect
    assert_log_clean log, "employee@example.test", "private words"
  end
end
