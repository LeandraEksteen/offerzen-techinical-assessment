require "test_helper"

class ScoreReaderTest < ActiveSupport::TestCase
  def read(*candidates)
    ScoreReader.read(candidates + [ nil ] * (4 - candidates.size))
  end

  # UT-1: the contract table, one row per shape in the seed
  test "every seeded shape maps to the agreed score or to nothing" do
    {
      "integer" => [ [ 85 ], 85 ], "float" => [ [ 85.5 ], 86 ], "float noise" => [ [ 84.99999 ], 85 ],
      "number as string" => [ [ "85" ], 85 ], "percent string" => [ [ "85%" ], 85 ], "decimal comma" => [ [ "84,5" ], 85 ],
      "alias assessment_score" => [ [ nil, 70 ], 70 ], "alias total_score" => [ [ nil, nil, 70 ], 70 ], "alias overall_score" => [ [ nil, nil, nil, 70 ], 70 ],
      "two keys, first wins" => [ [ 90, 60 ], 90 ], "proportion" => [ [ 0.85 ], nil ], "above range" => [ [ 150 ], nil ],
      "below range" => [ [ -5 ], nil ], "N/A text" => [ [ "N/A" ], nil ], "empty string" => [ [ "" ], nil ],
      "null score" => [ [ nil ], nil ], "no key" => [ [], nil ]
    }.each do |name, (candidates, expected)|
      actual = read(*candidates).score
      expected.nil? ? assert_nil(actual, name) : assert_equal(expected, actual, name)
    end
  end

  # UT-2
  test "the first valid value wins, a later key is used when an earlier one is invalid, and values are never combined" do
    assert_equal 70, read("N/A", 70, 80).score
    assert_equal "assessment_score", read("N/A", 70, 80).key
    assert_equal 60, read(nil, nil, nil, 60).score
    assert_equal 90, read(90, 60).score
    assert_equal 70, read(0.85, nil, 70).score
    assert_nil read("N/A", 150, 0.5).score
  end

  # UT-3
  test "strings are trimmed, may carry a percent sign with a space, and may use a decimal comma" do
    assert_equal 85, read(" 85 ").score
    assert_equal 85, read("85 %").score
    assert_equal 86, read("85.5").score
    assert_equal 2, read("1,5").score
    assert_equal 0, read("0%").score
  end

  test "text and ambiguous strings are not numbers" do
    {
      "N/A" => :not_numeric, "" => :not_numeric, "   " => :not_numeric, "85 out of 100" => :not_numeric,
      "1.234,5" => :not_numeric, "%85" => :not_numeric, "8 5" => :not_numeric, "-5" => :not_numeric, "1e2" => :not_numeric,
      "1,234" => :ambiguous_comma, "12,345" => :ambiguous_comma
    }.each do |text, reason|
      outcome = read(text)

      assert_nil outcome.score, text.inspect
      assert_equal reason, outcome.reason, text.inspect
    end
  end

  # UT-4
  test "0, 1 and 100 are valid" do
    assert_equal [ 0, 1, 100 ], [ read(0).score, read(1).score, read(100).score ]
    assert_equal 100, read(100.0).score
    assert_equal 1, read(1.0000001).score
  end

  test "below 0 and above 100 are out of range" do
    [ -1, -0.5, 100.4, 100.5, 1_000, 10**400 ].each do |value|
      assert_equal :out_of_range, read(value).reason, value.inspect
    end
  end

  test "a value strictly between 0 and 1 is not scaled and is a proportion" do
    [ 0.85, 0.5, 0.999, 0.0001, "0,85", "0.5" ].each do |value|
      outcome = read(value)

      assert_nil outcome.score, value.inspect
      assert_equal :proportion, outcome.reason, value.inspect
    end
  end

  # UT-5
  test "rounding is half up" do
    assert_equal 85, read(84.5).score
    assert_equal 84, read(84.4999).score
    assert_equal 85, read(84.99999).score
    assert_equal 85, read("84,5").score
    assert_equal 100, read(99.5).score
  end

  # UT-6
  test "the reader never raises" do
    exploding = Class.new { def nil? = raise("boom") }.new
    [ nil, [], [ nil ], [ {} ], [ [ 85 ] ], [ true ], [ false ], [ 10**400 ], [ "x" * 100_000 ], [ { "a" => { "b" => [ 1 ] } } ],
      [ Object.new ], [ Float::INFINITY ], [ Float::NAN ], [ exploding ] ].each do |candidates|
      assert_nothing_raised { ScoreReader.read(candidates) }
    end
    assert_equal :error, ScoreReader.read([ exploding ]).reason
  end

  test "objects, arrays and booleans are not numbers" do
    assert_equal :not_scalar, read({ "a" => 1 }).reason
    assert_equal :not_scalar, read([ 85 ]).reason
    assert_equal :boolean, read(true).reason
  end

  test "no candidate at all is missing" do
    assert_equal :missing, read.reason
    assert_equal :missing, ScoreReader.read(nil).reason
  end

  # UT-7
  test "the outcome names the key used, the rules applied and the reason for no score" do
    assert_equal({ score: 85, key: "score", rules: [], reason: nil }, read(85).to_h)
    assert_equal [ :string_number, :percent_sign ], read("85%").rules
    assert_equal [ :string_number, :decimal_comma, :round_half_up ], read("84,5").rules
    assert_equal [ :round_half_up ], read(84.99999).rules
    assert_equal [ :alias_key ], read(nil, 70).rules
    assert_equal({ score: nil, key: nil, rules: [], reason: :proportion }, read(0.85).to_h)
  end

  # UT-8
  test "a reader without one rule changes only what that rule did" do
    without = ->(rule) { ScoreReader.new(rules: ScoreReader::DEFAULT_RULES - [ rule ]) }

    assert_nil without.(:percent_sign).read([ "85%" ]).score
    assert_equal 85, without.(:percent_sign).read([ "85" ]).score
    assert_equal 85, without.(:percent_sign).read([ "84,5" ]).score

    assert_nil without.(:decimal_comma).read([ "84,5" ]).score
    assert_equal 85, without.(:decimal_comma).read([ "85%" ]).score

    assert_nil without.(:string_number).read([ "85" ]).score
    assert_equal 85, without.(:string_number).read([ 85 ]).score

    assert_equal 150, without.(:range).read([ 150 ]).score
    assert_nil without.(:range).read([ 0.85 ]).score

    assert_equal 1, without.(:proportion).read([ 0.85 ]).score
    assert_nil without.(:proportion).read([ 150 ]).score

    assert_equal 84.5, without.(:round_half_up).read([ 84.5 ]).score

    assert_equal :not_numeric, without.(:scalar_only).read([ true ]).reason
    assert_equal :boolean, ScoreReader.new.read([ true ]).reason
  end

  # UT-16
  test "the candidate SQL is generated from the single list of keys" do
    assert_equal ScoreReader::KEYS.size, ScoreReader.candidate_sql.size
    ScoreReader::KEYS.each { |key| assert_includes ScoreReader.candidate_sql, "responses_json->'#{key}'" }
    sql = Assessment.select(:id).with_score_candidates.to_sql
    ScoreReader::KEYS.each_index { |index| assert_includes sql, "AS score_candidate_#{index}" }
  end

  test "a loaded assessment reads its own score through the candidates" do
    company = create_company
    assessment = create_assessment(company: company, responses_json: { "assessment_score" => "70%" })

    loaded = Assessment.where(id: assessment.id).select(:id).with_score_candidates.first

    assert_equal 70, loaded.score_outcome.score
    assert_equal "assessment_score", loaded.score_outcome.key
  end

  test "a non-object root gives no candidates and no score" do
    company = create_company
    [ "text".to_json, [ 85 ], nil ].each do |root|
      assessment = create_assessment(company: company, responses_json: root)
      loaded = Assessment.where(id: assessment.id).select(:id).with_score_candidates.first

      assert_equal :missing, loaded.score_outcome.reason, root.inspect
    end
  end
end
