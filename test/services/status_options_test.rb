require "test_helper"

class StatusOptionsTest < ActiveSupport::TestCase
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @company = create_company(name: "Acme")
    @other = create_company(name: "Other")
  end

  teardown { Rails.cache = @original_cache }

  # UT-9
  test "lists the company's own statuses grouped and lowercased with no-status once" do
    [ "Complete", "complete ", "COMPLETE", "pending", "n/a", nil, "", "  " ].each { |status| create_assessment(company: @company, status: status) }
    create_assessment(company: @other, status: "secret-status-of-another-company")

    entries = StatusOptions.new(@company).entries

    assert_equal [ [ "complete", "complete" ], [ "n/a", "n/a" ], [ "pending", "pending" ], [ "(no status)", "__none__" ] ], entries
  end

  test "omits no-status when the company has none" do
    create_assessment(company: @company, status: "pending")

    assert_equal [ [ "pending", "pending" ] ], StatusOptions.new(@company).entries
  end

  test "does not change any stored status" do
    statuses = [ "Complete", "complete ", nil, "" ]
    statuses.each { |status| create_assessment(company: @company, status: status) }

    StatusOptions.new(@company).entries

    assert_equal statuses.map(&:to_s).sort, Assessment.where(company: @company).pluck(:status).map(&:to_s).sort
  end

  test "caches the list for ten minutes per company" do
    create_assessment(company: @company, status: "pending")
    assert_equal [ [ "pending", "pending" ] ], StatusOptions.new(@company).entries

    create_assessment(company: @company, status: "archived")
    assert_equal [ [ "pending", "pending" ] ], StatusOptions.new(@company).entries

    travel 11.minutes
    assert_equal [ [ "archived", "archived" ], [ "pending", "pending" ] ], StatusOptions.new(@company).entries
  end

  test "a status that appeared after the list was cached is still valid" do
    create_assessment(company: @company, status: "pending")
    options = StatusOptions.new(@company)
    options.entries

    create_assessment(company: @company, status: "archived")

    assert options.valid?("archived")
    assert_not options.valid?("never-seen")
    assert_not options.valid?(StatusOptions::NONE)
  end
end
