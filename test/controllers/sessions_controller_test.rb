require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  # UT-3
  test "valid sign-in shows the admin's company on the home page" do
    admin = create_admin(company: create_company(name: "Acme Test"))

    post session_url, params: { email: admin.email, password: TEST_PASSWORD }
    assert_redirected_to root_url

    follow_redirect!
    assert_response :success
    assert_select "h1", "Acme Test"
  end

  test "sign-out ends the session" do
    admin = create_admin
    post session_url, params: { email: admin.email, password: TEST_PASSWORD }

    delete session_url
    assert_redirected_to new_session_url

    get root_url
    assert_redirected_to new_session_url
  end

  # UT-4
  test "wrong password creates no session" do
    admin = create_admin

    post session_url, params: { email: admin.email, password: "wrong" }
    assert_response :unprocessable_entity

    get root_url
    assert_redirected_to new_session_url
  end

  test "unknown email creates no session" do
    post session_url, params: { email: "nobody@example.test", password: TEST_PASSWORD }

    assert_response :unprocessable_entity
  end

  # UT-5
  test "unauthenticated request is redirected to sign-in" do
    get root_url

    assert_redirected_to new_session_url
  end

  test "sign-in page is reachable without signing in" do
    get new_session_url

    assert_response :success
  end

  # UT-6
  test "a company_id parameter does not change the company shown" do
    own = create_company(name: "Own Company")
    other = create_company(name: "Other Company")
    admin = create_admin(company: own)
    post session_url, params: { email: admin.email, password: TEST_PASSWORD }

    get root_url, params: { company_id: other.id }

    assert_select "h1", "Own Company"
  end
end
