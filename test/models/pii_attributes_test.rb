require "test_helper"

class PiiAttributesTest < ActiveSupport::TestCase
  # UT-1
  test "models declare their PII attributes once" do
    assert_equal %w[ employee_email responses_json ], Assessment.pii_attribute_names.sort
    assert_equal %w[ email name ], Employee.pii_attribute_names.sort
    assert_equal %w[ email password_digest ], Admin.pii_attribute_names.sort
    assert_empty Company.try(:pii_attribute_names).to_a
  end

  test "declaring twice does not duplicate names" do
    before_names = Assessment.pii_attribute_names
    Assessment.pii_attributes :employee_email

    assert_equal before_names, Assessment.pii_attribute_names
    assert_equal Pii::Registry.all_names.uniq, Pii::Registry.all_names
  end

  # UT-3
  test "inspect redacts declared attributes and still shows the id" do
    company = create_company
    assessment = create_assessment(company: company, employee_email: "x@example.test", responses_json: { "comments" => "private note" })

    text = assessment.inspect

    assert_includes text, "id: #{assessment.id}"
    assert_not_includes text, "x@example.test"
    assert_not_includes text, "private note"
    assert_includes text, "[FILTERED]"
    assert_not_includes assessment.employee.inspect, "Test Employee"
    assert_not_includes create_admin(company: company).inspect, "admin@example.test"
  end
end
