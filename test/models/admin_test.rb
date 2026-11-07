require "test_helper"

class AdminTest < ActiveSupport::TestCase
  # UT-2
  test "requires a company" do
    admin = Admin.new(email: "admin@example.test", password: TEST_PASSWORD)

    assert_not admin.valid?
    assert admin.errors[:company].any?
  end

  test "email is unique regardless of case and whitespace" do
    create_admin(email: "admin@example.test")
    duplicate = Admin.new(company: create_company(name: "Other"), email: " ADMIN@example.test ", password: TEST_PASSWORD)

    assert_not duplicate.valid?
    assert duplicate.errors[:email].any?
  end

  test "authenticates with the right password only" do
    admin = create_admin

    assert admin.authenticate(TEST_PASSWORD)
    assert_not admin.authenticate("wrong")
  end
end
