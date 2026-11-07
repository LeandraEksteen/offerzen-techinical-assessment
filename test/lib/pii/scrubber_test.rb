require "test_helper"

class PiiScrubberTest < ActiveSupport::TestCase
  setup do
    # Make sure the model declarations have run.
    [ Assessment, Employee, Admin ]
  end

  # UT-4
  test "redacts email addresses anywhere in text" do
    out = Pii::Scrubber.scrub_text("duplicate key value violates unique constraint (a.b+c@example.test) failed")

    assert_not_includes out, "a.b+c@example.test"
    assert_includes out, "[FILTERED_EMAIL]"
  end

  # UT-5
  test "redacts declared attribute values in a Ruby hash" do
    text = %({"responses_json"=>{"answers"=>[{"question"=>"q1", "value"=>5}], "comments"=>"call 555-0100"}, "status"=>"done"})
    out = Pii::Scrubber.scrub_text(text)

    assert_not_includes out, "555-0100"
    assert_not_includes out, "q1"
    assert_includes out, %("status"=>"done")
  end

  test "redacts declared attribute values in JSON" do
    text = %({"employee_email":"x@example.test","responses_json":{"score":85,"comments":"private note"},"status":"done"})
    out = Pii::Scrubber.scrub_text(text)

    assert_not_includes out, "private note"
    assert_not_includes out, "x@example.test"
    assert_includes out, %("status":"done")
  end

  test "redacts declared attribute values after key-colon" do
    out = Pii::Scrubber.scrub_text(%(#<Employee id: 5, name: "Alex Example", status: "done">))

    assert_not_includes out, "Alex Example"
    assert_includes out, "id: 5"
    assert_includes out, %(status: "done")
  end

  test "redacts declared attribute values after SQL equals, including doubled quotes" do
    out = Pii::Scrubber.scrub_text(%(WHERE "employees"."name" = 'O''Brien Example' AND "employees"."id" = 7))

    assert_not_includes out, "Brien"
    assert_includes out, %("employees"."id" = 7)
  end

  test "redacts declared attribute values in bind arrays" do
    out = Pii::Scrubber.scrub_text(%([["name", "Zelda Placeholder"], ["status", "done"]]))

    assert_not_includes out, "Zelda"
    assert_includes out, %(["status", "done"])
  end

  test "redacts a JSON blob inside a SQL literal and keeps the rest of the statement" do
    out = Pii::Scrubber.scrub_text(%(UPDATE assessments SET responses_json = '{"answers":[{"q":"q1"}],"comments":"secret text"}' WHERE id = 1))

    assert_not_includes out, "secret text"
    assert_includes out, "WHERE id = 1"
  end

  # UT-6
  test "leaves ordinary text alone" do
    text = "Started GET /session/new for 127.0.0.1 at 2026-11-07 status=done count: 5"

    assert_equal text, Pii::Scrubber.scrub_text(text)
  end

  test "returns non-strings unchanged" do
    assert_nil Pii::Scrubber.scrub_text(nil)
    assert_equal 5, Pii::Scrubber.scrub_text(5)
  end

  test "handles unbalanced and hostile input without raising or hanging" do
    hostile = [ "responses_json: " + ("{" * 100_000), %(responses_json: {"a": [1, 2), %("responses_json" => "unterminated), "name: " ]

    Timeout.timeout(5) do
      hostile.each do |text|
        assert_nothing_raised { Pii::Scrubber.scrub_text(text) }
      end
    end
    assert_includes Pii::Scrubber.scrub_text(%(responses_json: {"a": [1, 2)), "[FILTERED]"
  end

  test "handles multibyte text" do
    out = Pii::Scrubber.scrub_text(%(name: "Zoë Müller" status: "done" – ok))

    assert_not_includes out, "Müller"
    assert_includes out, %(status: "done" – ok)
  end

  # UT-7
  test "scrub_attributes replaces declared attributes and keeps the rest" do
    out = Pii::Scrubber.scrub_attributes(Assessment, { "id" => 1, employee_email: "x@example.test", "responses_json" => { "a" => 1 }, "status" => "done" })

    assert_equal 1, out["id"]
    assert_equal "done", out["status"]
    assert_equal "[REDACTED]", out[:employee_email]
    assert_equal "[REDACTED]", out["responses_json"]
  end
end
