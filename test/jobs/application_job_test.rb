require "test_helper"

class PiiProbeJob < ApplicationJob
  def perform(*); end
end

class ApplicationJobTest < ActiveJob::TestCase
  # UT-10
  test "rejects strings, hashes and emails as arguments" do
    assert_raises(ArgumentError) { PiiProbeJob.perform_later("jordan.sample@example.test") }
    assert_raises(ArgumentError) { PiiProbeJob.perform_later({ email: "jordan.sample@example.test" }) }
    assert_raises(ArgumentError) { PiiProbeJob.perform_later(1, "name") }
    assert_enqueued_jobs 0
  end

  test "the error message does not repeat the argument" do
    error = assert_raises(ArgumentError) { PiiProbeJob.perform_later("jordan.sample@example.test") }

    assert_not_includes error.message, "jordan.sample@example.test"
  end

  test "accepts ids, nil and records" do
    assessment = create_assessment(company: create_company)

    assert_nothing_raised do
      PiiProbeJob.perform_later(assessment.id)
      PiiProbeJob.perform_later(nil)
      PiiProbeJob.perform_later(assessment)
    end
    assert_enqueued_jobs 3
  end

  test "job arguments are not written to the log" do
    assessment = create_assessment(company: create_company)

    log = capture_log { PiiProbeJob.perform_later(assessment.id) }

    assert_includes log, "Enqueued PiiProbeJob"
    assert_not_includes log, "Arguments"
    assert_not_includes log, "with arguments"
  end
end
