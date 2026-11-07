require "test_helper"

class LogHygieneTest < ActionDispatch::IntegrationTest
  # UT-2
  test "declared attributes are filtered from the logged request parameters" do
    log = capture_log do
      get new_session_url, params: { responses_json: "SECRET-BLOB", name: "Zelda Placeholder", status: "done" }
    end

    assert_log_clean log, "SECRET-BLOB", "Zelda Placeholder"
    assert_includes log, %("responses_json"=>[FILTERED])
    assert_includes log, %("status"=>"done")
  end

  test "the parameter filter alone, without the log formatter, already hides declared attributes" do
    log = capture_log(scrub: false) do
      get new_session_url, params: { responses_json: "SECRET-BLOB", employee_email: "x@example.test" }
    end

    assert_log_clean log, "SECRET-BLOB", "x@example.test"
  end

  # UT-9
  test "signing in and loading the home page leaves no email or password in the log" do
    admin = create_admin(email: "jordan.sample@example.test")

    log = capture_log do
      post session_url, params: { email: admin.email, password: TEST_PASSWORD }
      follow_redirect!
      post session_url, params: { email: admin.email, password: "wrong-guess-value" }
    end

    assert_log_clean log, "jordan.sample@example.test", TEST_PASSWORD, "wrong-guess-value"
    assert_includes log, "Processing by SessionsController#create"
  end

  # UT-8
  test "the app logger is configured with the scrubbing formatter" do
    assert_kind_of Pii::LogFormatter, Rails.application.config.log_formatter
  end

  test "the formatter scrubs a normal line" do
    line = Pii::LogFormatter.new.call("INFO", Time.now, nil, "welcome jordan.sample@example.test")

    assert_not_includes line, "jordan.sample@example.test"
    assert_includes line, "welcome"
  end

  test "an error log carrying an email is scrubbed" do
    error = ActiveRecord::RecordNotUnique.new(%(duplicate key value violates unique constraint: Key (email)=(jordan.sample@example.test) already exists.))

    log = capture_log { Rails.logger.error(error) }

    assert_log_clean log, "jordan.sample@example.test"
    assert_includes log, "RecordNotUnique"
  end

  # UT-11
  test "a query with bind values on declared columns does not log the values" do
    create_assessment(company: create_company)

    log = capture_log do
      Employee.where(name: "Zelda Placeholder").to_a
      Employee.where("name = 'Zelda Placeholder'").to_a
    end

    assert_log_clean log, "Zelda Placeholder"
    assert_includes log, "employees"
  end
end
