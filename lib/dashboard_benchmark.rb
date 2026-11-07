# Repeatable dashboard benchmark. Each scenario signs in as a seeded admin and
# requests the dashboard: one warm-up, then the median of several runs.
# Prints a markdown table. A scenario that exceeds its time limit is reported as
# "did not finish" (a valid baseline for a page that is too slow to finish).
#
#   bin/rails benchmark:dashboard                (all scenarios)
#   SCENARIOS=normal,company2 RUNS=3 bin/rails benchmark:dashboard
#
# Run with BULLET=off MINI_PROFILER=off RAILS_LOG_LEVEL=warn so the diagnosis
# tools and log writing are not part of the timing. Development environment only.
class DashboardBenchmark
  Scenario = Struct.new(:key, :label, :admin_email, :path, :runs, :limit_seconds, keyword_init: true)

  def self.scenarios(runs: 5, big_limit: 600)
    [
      Scenario.new(key: "normal", label: "Company 02, assessment dates in 2024, page 1", admin_email: "admin2@company-2.example.test",
                   path: "/dashboard?from=2024-01-01&to=2024-12-31", runs: runs, limit_seconds: 120),
      Scenario.new(key: "company2", label: "Company 02, all rows, page 1", admin_email: "admin2@company-2.example.test",
                   path: "/dashboard", runs: runs, limit_seconds: 300),
      Scenario.new(key: "big", label: "Company 01 (largest), all rows, page 1", admin_email: "admin1@company-1.example.test",
                   path: "/dashboard", runs: runs, limit_seconds: big_limit),
      Scenario.new(key: "deep", label: "Company 01 (largest), page 3,000 (offset 149,950)", admin_email: "admin1@company-1.example.test",
                   path: "/dashboard?page=3000", runs: runs, limit_seconds: big_limit)
    ]
  end

  def initialize(keys:, runs: 5, big_limit: 600, password: AssessmentSeeder::DEFAULT_PASSWORD, output: $stdout, enforce_development: true)
    @enforce_development = enforce_development
    @scenarios = self.class.scenarios(runs: runs, big_limit: big_limit).select { |scenario| keys.include?(scenario.key) }
    @password = password
    @output = output
  end

  def call
    raise "The benchmark runs in development only" if @enforce_development && !Rails.env.development?

    @output.puts "| Scenario | Rows | SQL queries run | Query-cache hits | Median ms (min-max) | HTML size | Result |"
    @output.puts "|---|---|---|---|---|---|---|"
    @scenarios.each { |scenario| @output.puts run(scenario) }
  end

  private

  def run(scenario)
    probe = DashboardProbe.new(email: scenario.admin_email, password: @password)
    probe.measure(scenario.path) if scenario.runs > 1 # warm-up
    results = Array.new(scenario.runs) { Timeout.timeout(scenario.limit_seconds) { probe.measure(scenario.path) } }
    ms = results.map(&:ms).sort
    last = results.last
    format_row(scenario, last.rows, last.queries, last.cache_hits, "#{ms[ms.size / 2]} (#{ms.first}-#{ms.last})", "#{(last.bytes / 1024.0).round} KB", "HTTP #{last.status}")
  rescue Timeout::Error
    format_row(scenario, "-", "-", "-", "-", "-", "did not finish within #{scenario.limit_seconds} s")
  end

  def format_row(scenario, rows, queries, cache_hits, ms, size, result)
    "| #{scenario.label} | #{rows} | #{queries} | #{cache_hits} | #{ms} | #{size} | #{result} |"
  end
end
