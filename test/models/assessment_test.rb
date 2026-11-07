require "test_helper"

class AssessmentTest < ActiveSupport::TestCase
  # UT-1
  test "belongs to a company and employee and allows loose status and responses" do
    company = create_company
    assessment = create_assessment(company: company, status: nil, responses_json: nil)

    assert_equal company, assessment.company
    assert_equal company, assessment.employee.company
    assert_nil assessment.status
    assert_nil assessment.responses_json
  end

  test "stores any legacy status text and arbitrary json" do
    company = create_company
    assessment = create_assessment(company: company, status: " n/a ", responses_json: { "score" => "85%" })

    assert_equal " n/a ", assessment.reload.status
    assert_equal "85%", assessment.responses_json["score"]
  end

  # UT-2
  test "requires an assessment date" do
    company = create_company
    employee = company.employees.create!(name: "Test Employee", email: "employee@example.test")
    assessment = Assessment.new(company: company, employee: employee)

    assert_not assessment.valid?
    assert_includes assessment.errors[:assessment_date], "can't be blank"
  end

  test "requires a company" do
    company = create_company
    employee = company.employees.create!(name: "Test Employee", email: "employee@example.test")
    assessment = Assessment.new(employee: employee, assessment_date: Date.current)

    assert_not assessment.valid?
    assert assessment.errors[:company].any?
  end

  # ---- Status rules (Req 29, 40, 44) ----

  def new_assessment(**attributes)
    company = create_company
    employee = company.employees.create!(name: "Test Employee", email: "employee@example.test")
    Assessment.new({ company: company, employee: employee, assessment_date: Date.current }.merge(attributes))
  end

  def with_cutover(date)
    original = Rails.configuration.x.status_cutover_date
    Rails.configuration.x.status_cutover_date = date
    yield
  ensure
    Rails.configuration.x.status_cutover_date = original
  end

  # UT-1
  test "the five canonical statuses save on create and on change" do
    Assessment::STATUSES.each do |status|
      assessment = new_assessment(status: status)

      assert assessment.save, "#{status}: #{assessment.errors.full_messages}"
      assert assessment.update(status: "archived")
    end
    assert_equal %w[ pending in_progress completed needs_follow_up archived ], Assessment::STATUSES
  end

  # UT-2
  test "case, whitespace, unknown and blank variants fail with a clear message" do
    [ "Pending", "PENDING", " pending", "completed ", "complete", "done", "in progress", "", " " ].each do |value|
      created = new_assessment(status: value)
      assert_not created.save, "#{value.inspect} should be rejected on create"
      assert_equal [ "must be one of: pending, in_progress, completed, needs_follow_up, archived" ], created.errors[:status]

      saved = new_assessment(status: "pending").tap(&:save!)
      assert_not saved.update(status: value), "#{value.inspect} should be rejected on change"
      assert_equal "pending", saved.reload.status
    end
  end

  # UT-3
  test "updating another field on a legacy row with a dirty status still succeeds" do
    legacy = create_assessment(company: create_company, status: "Complete ")

    assert legacy.update(assessment_date: Date.new(2020, 1, 2))
    assert_equal "Complete ", legacy.reload.status

    partly_loaded = Assessment.select(:id, :company_id, :employee_id, :assessment_date, :status).find(legacy.id)
    assert partly_loaded.update(assessment_date: Date.new(2021, 1, 2))
  end

  # UT-4
  test "from a dirty status, another non-canonical value fails and a canonical one works" do
    legacy = create_assessment(company: create_company, status: "Complete ")

    assert_not legacy.update(status: "complete")
    assert_equal "Complete ", legacy.reload.status
    assert legacy.update(status: "completed")
    assert_equal "completed", legacy.reload.status
  end

  # UT-5
  test "creating with no status stores pending" do
    assessment = new_assessment(status: nil)

    assessment.save!

    assert_equal "pending", assessment.reload.status
  end

  # UT-6
  test "creating with a non-canonical status fails, an empty string included" do
    [ "Complete", "" ].each do |value|
      assert_not new_assessment(status: value).save
    end
  end

  # UT-7
  test "before the cut-over date a non-canonical status saves and one count line is logged without the value" do
    with_cutover(Date.current + 1) do
      before = Assessment.would_be_rejections
      assessment = new_assessment(status: "Secret Legacy Value")

      log = capture_log { assert assessment.save }

      assert_equal "Secret Legacy Value", assessment.reload.status
      assert_equal before + 1, Assessment.would_be_rejections
      assert_equal 1, log.scan("status validation: would reject after cut-over (count=#{before + 1})").size
      count_line = log.lines.grep(/would reject/).first
      assert_no_match(/Secret Legacy Value|employee@example\.test/, count_line)
    end
  end

  test "before the date nothing is counted for a canonical status or an untouched legacy status" do
    with_cutover(Date.current + 1) do
      legacy = create_assessment(company: create_company, status: "Complete ")
      before = Assessment.would_be_rejections

      assert new_assessment(status: "archived").save
      assert legacy.update(assessment_date: Date.new(2020, 1, 2))

      assert_equal before, Assessment.would_be_rejections
    end
  end

  # UT-8
  test "on and after the cut-over date a non-canonical status is rejected and not counted" do
    [ Date.current, Date.current - 10 ].each do |cutover|
      with_cutover(cutover) do
        before = Assessment.would_be_rejections
        assessment = new_assessment(status: "done")

        log = capture_log { assert_not assessment.save }

        assert_equal before, Assessment.would_be_rejections
        assert_no_match(/would reject/, log)
      end
    end
  end

  # UT-9
  test "the day before the date is allowed, the day itself is enforced, and no date enforces" do
    cutover = Date.new(2030, 6, 15)
    with_cutover(cutover) do
      assert_not Assessment.status_rule_enforced?(cutover - 1)
      assert Assessment.status_rule_enforced?(cutover)
      assert Assessment.status_rule_enforced?(cutover + 1)
    end
    with_cutover(nil) { assert Assessment.status_rule_enforced?(Date.new(1999, 1, 1)) }
  end

  test "the configured date is read from STATUS_CUTOVER_DATE and an invalid value stops boot" do
    script = "print Rails.configuration.x.status_cutover_date.inspect"
    env = { "RAILS_ENV" => "test", "BULLET" => "off" }

    valid = IO.popen(env.merge("STATUS_CUTOVER_DATE" => "2030-06-15"), [ "bin/rails", "runner", script ], err: File::NULL, &:read)
    assert_equal "Sat, 15 Jun 2030", valid

    unset = IO.popen(env.merge("STATUS_CUTOVER_DATE" => ""), [ "bin/rails", "runner", script ], err: File::NULL, &:read)
    assert_equal "nil", unset

    invalid = IO.popen(env.merge("STATUS_CUTOVER_DATE" => "next tuesday"), [ "bin/rails", "runner", script ], err: [ :child, :out ], &:read)
    assert_match(/STATUS_CUTOVER_DATE must be an ISO date/, invalid)
  end

  # UT-14
  test "the rejection message and the count line hold no submitted value" do
    assessment = new_assessment(status: "Leaky Value")
    assessment.valid?
    assert_no_match(/Leaky Value/, assessment.errors.full_messages.join)
  end
end
