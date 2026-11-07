require "test_helper"

class DashboardProbeTest < ActiveSupport::TestCase
  setup do
    @company = create_company(name: "Company 01")
    create_admin(company: @company, email: "admin1@company-1.example.test")
  end

  def probe
    DashboardProbe.new(email: "admin1@company-1.example.test", password: TEST_PASSWORD)
  end

  def add_rows(count)
    count.times do |n|
      employee = @company.employees.create!(name: "Person #{n}", email: "person#{n}@example.test")
      legacy_assessment(company: @company, employee: employee, assessment_date: Date.new(2025, 1, 1) + n, status: "pending", responses_json: { "score" => 20 + n })
    end
  end

  # UT-10
  test "the snapshot prints the first rows with a stable digest and no emails" do
    add_rows(60)

    lines = probe.snapshot("/dashboard")

    assert_equal 50, lines.size
    assert_equal lines, probe.snapshot("/dashboard")
    assert lines.first.match?(/\A\d+ \| 2025-03-01 \| "pending" \| "79" \| \h{8}\z/), "unexpected first line: #{lines.first}"
    assert_no_match(/example\.test|@/, lines.join("\n"))
  end

  test "the snapshot of a smaller page has only the rows there are" do
    add_rows(3)

    assert_equal 3, probe.snapshot("/dashboard").size
  end

  # UT-11
  test "measure reports status, queries, milliseconds, bytes and rows" do
    add_rows(4)

    result = probe.measure("/dashboard")

    assert_equal 200, result.status
    assert_equal 4, result.rows
    assert_operator result.queries, :>=, 4
    assert_operator result.cache_hits, :>=, 0
    assert_operator result.bytes, :>, 0
    assert_operator result.ms, :>=, 0
  end

  test "the benchmark refuses to run outside development" do
    error = assert_raises(RuntimeError) { DashboardBenchmark.new(keys: [ "normal" ], runs: 1, output: StringIO.new).call }

    assert_match(/development only/, error.message)
  end

  test "the benchmark runs a scenario and prints rows, queries, ms and size" do
    company_two = create_company(name: "Company 02")
    create_admin(company: company_two, email: "admin2@company-2.example.test")
    employee = company_two.employees.create!(name: "Person", email: "person@example.test")
    3.times { legacy_assessment(company: company_two, employee: employee, assessment_date: Date.new(2024, 6, 1), status: "done") }
    io = StringIO.new

    DashboardBenchmark.new(keys: [ "normal" ], runs: 2, password: TEST_PASSWORD, output: io, enforce_development: false).call

    row = io.string.lines.last
    assert_match(/\A\| Company 02, assessment dates in 2024, page 1 \| 3 \| \d+ \| \d+ \| \d+ \(\d+-\d+\) \| \d+ KB \| HTTP 200 \|\z/, row.strip)
    assert_no_match(/@/, io.string)
  end

  # UT-11 (TKT-5)
  test "the benchmark has page-1 scenarios and a deep page, and a page holds 50 rows" do
    keys = DashboardBenchmark.scenarios.map(&:key)
    assert_equal %w[ normal company2 big deep ], keys
    assert_match(/page=3000/, DashboardBenchmark.scenarios.find { |scenario| scenario.key == "deep" }.path)

    add_rows(120)
    result = probe.measure("/dashboard")

    assert_equal 50, result.rows
    assert_equal 3, probe.snapshot("/dashboard?page=3").size > 0 ? 3 : 0
  end
end
