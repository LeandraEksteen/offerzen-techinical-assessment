require "test_helper"

class ScoreReportTest < ActiveSupport::TestCase
  setup do
    @company = create_company(name: "Acme")
    @counter = 0
  end

  def add(json)
    @counter += 1
    employee = @company.employees.create!(name: "E#{@counter}", email: "e#{@counter}@example.test")
    legacy_assessment(company: @company, employee: employee, assessment_date: Date.current, responses_json: json)
  end

  def report(batch: 3)
    io = StringIO.new
    ScoreReport.new(output: io, batch: batch).call
    io.string
  end

  # UT-13
  test "prints per-case counts, per-rule counts, reasons and examples across batches" do
    [ { "score" => 85 }, { "score" => 85 }, { "score" => "85" }, { "score" => "85%" }, { "score" => "84,5" }, { "assessment_score" => 70 },
      { "score" => 84.5 }, { "score" => 0.85 }, { "score" => "N/A" }, { "score" => 150 }, { "comments" => "x" }, "text".to_json, [ 1 ], nil ].each { |json| add(json) }

    out = report

    assert_match(/Score report: 14 assessments \(read only/, out)
    assert_match(/valid_as_is\s+2\b/, out)
    assert_match(/string_converted\s+1\b/, out)
    assert_match(/percent_stripped\s+1\b/, out)
    assert_match(/decimal_comma\s+1\b/, out)
    assert_match(/rounded\s+1\b/, out)
    assert_match(/alias_key\s+1\b/, out)
    assert_match(/proportion_rejected\s+1\b/, out)
    assert_match(/other_invalid\s+2\b/, out)
    assert_match(/missing\s+4\b.*root is not an object: 3/, out)
    assert_match(/shown with a score\s+7\b/, out)
    assert_match(/percent_sign\s+1\b/, out)
    assert_match(/not_numeric\s+1\b/, out)
    assert_match(/out_of_range\s+1\b/, out)
    assert_match(/\| N\/A \| not_numeric/, out)
    assert_match(/\| 85% \| 85/, out)
  end

  test "prints at most five examples per case" do
    9.times { add({ "score" => 50 }) }

    examples = report.lines.grep(/\A    \d+ \| 50 \| 50/)

    assert_equal 5, examples.size
  end

  test "a free-text token is described, never printed, and no email appears" do
    add({ "score" => "my knee hurts, please call Alex Example on 555-0100 or jordan@example.test" })
    add({ "score" => "N/A" })

    out = report

    assert_match(/\[text, \d+ characters\]/, out)
    assert_no_match(/knee|Alex|555-0100|jordan|@|example\.test/, out)
    assert_match(/\| N\/A \|/, out)
  end

  test "even a short word is described, not printed, but placeholder words are" do
    [ "Alex", "Alex Example", "none", "NA", "TBD", "85 %" ].each { |token| add({ "score" => token }) }

    out = report

    assert_no_match(/Alex/, out)
    assert_match(/\| none \|/, out)
    assert_match(/\| NA \|/, out)
    assert_match(/\| TBD \|/, out)
    assert_match(/\| 85 % \|/, out)
    assert_equal 2, out.scan(/\[text, \d+ characters\]/).size
  end

  test "an empty table reports zero rows" do
    out = report

    assert_match(/Score report: 0 assessments/, out)
  end

  test "it writes nothing" do
    add({ "score" => "85%" })
    before = Assessment.pluck(:id, :responses_json, :updated_at)

    report

    assert_equal before, Assessment.pluck(:id, :responses_json, :updated_at)
  end
end
