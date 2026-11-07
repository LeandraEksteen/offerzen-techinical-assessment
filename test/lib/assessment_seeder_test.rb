require "test_helper"

class AssessmentSeederTest < ActiveSupport::TestCase
  # bin/ci seeds the test database after running the tests, so these tests must
  # not assume empty tables. The deletes are rolled back with the test transaction.
  setup do
    [ Assessment, Admin, Employee, Company ].each(&:delete_all)
  end

  def seed(total: 400, companies: 4)
    AssessmentSeeder.new(total: total, companies: companies, output: StringIO.new).call
  end

  # UT-7
  test "creates the requested counts with one dominant company" do
    seed(total: 400, companies: 4)

    assert_equal 400, Assessment.count
    assert_equal 4, Company.count
    assert_equal 4, Admin.count
    counts = Assessment.group(:company_id).count.values.sort

    assert_equal 160, counts.last
    assert_equal 400, counts.sum
  end

  test "includes every dirty status variant" do
    seed

    stored = Assessment.pluck(:status).uniq
    AssessmentSeeder::STATUS_VARIANTS.each do |status, _weight|
      assert_includes stored, status, "missing status variant #{status.inspect}"
    end
  end

  test "includes every score shape" do
    seed
    roots = Assessment.pluck(:responses_json)

    assert roots.any? { |json| json.is_a?(Hash) && json["score"].is_a?(Integer) }, "integer score"
    assert roots.any? { |json| json.is_a?(Hash) && json["score"].is_a?(Float) }, "float score"
    assert roots.any? { |json| json.is_a?(Hash) && json["score"].is_a?(String) && json["score"].end_with?("%") }, "percent string"
    assert roots.any? { |json| json.is_a?(Hash) && json["score"].is_a?(String) && json["score"].include?(",") }, "decimal comma"
    assert roots.any? { |json| json.is_a?(Hash) && json.key?("assessment_score") }, "alias assessment_score"
    assert roots.any? { |json| json.is_a?(Hash) && json.key?("total_score") }, "alias total_score"
    assert roots.any? { |json| json.is_a?(Hash) && json.key?("overall_score") }, "alias overall_score"
    assert roots.any? { |json| json.is_a?(Hash) && json["score"].is_a?(Float) && json["score"] < 1 }, "proportion"
    assert roots.any? { |json| json.is_a?(Hash) && json["score"].to_s.then { |v| v.match?(/\A-?\d+\z/) && (v.to_i > 100 || v.to_i < 0) } }, "out of range"
    assert roots.any? { |json| json.is_a?(Hash) && json.key?("score") && json["score"].nil? }, "null score"
    assert roots.any? { |json| json.is_a?(Hash) && !json.key?("score") && !json.key?("assessment_score") && !json.key?("total_score") && !json.key?("overall_score") }, "missing key"
    assert roots.any? { |json| json.is_a?(String) }, "double encoded json string"
    assert roots.any? { |json| json.is_a?(Array) }, "array root"
    assert roots.any?(&:nil?), "null root"
  end

  test "assessment dates include scheduled future dates and ten years of history" do
    seed(total: 2000, companies: 4)
    dates = Assessment.pluck(:assessment_date)

    assert dates.any? { |date| date > Date.current }, "no future dates"
    assert dates.min < 9.years.ago.to_date, "history too short"
  end

  test "is deterministic for the same seed" do
    seed(total: 200, companies: 2)
    first = Assessment.order(:id).pluck(:status, :assessment_date)
    Assessment.delete_all
    Admin.delete_all
    Employee.delete_all
    Company.delete_all

    seed(total: 200, companies: 2)

    assert_equal first, Assessment.order(:id).pluck(:status, :assessment_date)
  end

  test "does not write inserted values to the log" do
    io = StringIO.new
    original_logger = ActiveRecord::Base.logger
    begin
      ActiveRecord::Base.logger = ActiveSupport::Logger.new(io)
      seed(total: 50, companies: 2)
    ensure
      ActiveRecord::Base.logger = original_logger
    end

    assert_not_includes io.string, "example.test"
    assert_not_includes io.string, "INSERT INTO"
  end

  test "refuses to run when assessments already exist" do
    seed(total: 50, companies: 2)

    assert_raises(RuntimeError) { seed(total: 50, companies: 2) }
  end

  # UT-8
  test "refuses to run in production" do
    original_env = Rails.env
    error = nil
    begin
      Rails.env = "production"
      error = assert_raises(RuntimeError) { seed(total: 10, companies: 2) }
    ensure
      Rails.env = original_env
    end

    assert_match(/production/, error.message)
    assert_equal 0, Assessment.count
  end
end
