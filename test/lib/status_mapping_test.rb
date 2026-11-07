require "test_helper"

class StatusMappingTest < ActiveSupport::TestCase
  def build(overrides = {})
    StatusMapping.new({ "version" => 1, "approved" => false, "mapping" => { "done" => "completed", "__none__" => "pending" } }.merge(overrides))
  end

  # UT-7
  test "normalises like StatusOptions: trimmed, lower-cased, nothing left means none" do
    assert_equal "complete", StatusMapping.normalise("  Complete\t")
    assert_equal "complete", StatusMapping.normalise("COMPLETE")
    assert_equal "in progress", StatusMapping.normalise(" In Progress ")
    [ nil, "", " ", " \t\r\n " ].each { |blank| assert_equal "__none__", StatusMapping.normalise(blank), blank.inspect }
    assert_equal StatusOptions::NONE, StatusMapping::NONE
  end

  test "agrees with the SQL grouping StatusOptions uses" do
    company = create_company
    values = [ "Complete ", "COMPLETE", " done\n", nil, "", "  ", "n/a" ]
    values.each { |status| create_assessment(company: company, status: status) }

    sql_groups = company.assessments.distinct.pluck(Arel.sql(StatusOptions::NORMALISED_SQL)).map { |value| value || StatusMapping::NONE }.sort
    ruby_groups = values.map { |value| StatusMapping.normalise(value) }.uniq.sort

    assert_equal sql_groups, ruby_groups
  end

  test "looks a stored value up by its normalised form" do
    mapping = build

    assert_equal "completed", mapping.target_for(" Done ")
    assert_equal "pending", mapping.target_for(nil)
    assert_equal "pending", mapping.target_for("   ")
    assert_nil mapping.target_for("n/a")
  end

  test "an unapproved file is a draft and an approved one needs who and when" do
    assert build.draft?
    assert_not build.approved?

    assert_raises(StatusMapping::Invalid) { build("approved" => true) }
    approved = build("approved" => true, "approved_by" => "Assessor lead", "approved_on" => "2026-12-01")
    assert approved.approved?
    assert_not approved.draft?
  end

  test "rejects targets outside the five statuses" do
    error = assert_raises(StatusMapping::Invalid) { build("mapping" => { "done" => "finished" }) }

    assert_match(/not one of pending, in_progress, completed, needs_follow_up, archived/, error.message)
  end

  test "rejects keys that are not normalised, so two spellings can never collide" do
    [ "Done", " done", "done ", "" ].each do |key|
      assert_raises(StatusMapping::Invalid, key.inspect) { build("mapping" => { key => "completed" }) }
    end
  end

  test "rejects a malformed file" do
    assert_raises(StatusMapping::Invalid) { StatusMapping.new(nil) }
    assert_raises(StatusMapping::Invalid) { build("version" => "one") }
    assert_raises(StatusMapping::Invalid) { build("approved" => "yes") }
    assert_raises(StatusMapping::Invalid) { build("mapping" => [ "done" ]) }
  end

  test "load returns nil when there is no file" do
    assert_nil StatusMapping.load(Rails.root.join("tmp/no-such-mapping.yml"))
  end

  # UT-8
  test "the committed draft mapping loads, is a draft and maps only to canonical statuses" do
    mapping = StatusMapping.load

    assert mapping, "db/status_mapping.yml is missing"
    assert mapping.draft?
    assert_equal "completed", mapping.target_for("Complete ")
    assert_equal "completed", mapping.target_for("comp")
    assert_nil mapping.target_for("n/a"), "n/a is deliberately unmapped"
    assert_nil mapping.target_for(nil), "NULL, empty and blank are deliberately unmapped"
  end
end
