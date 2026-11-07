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
end
