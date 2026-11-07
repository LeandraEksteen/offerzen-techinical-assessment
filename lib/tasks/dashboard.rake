namespace :benchmark do
  desc "Time the dashboard (SCENARIOS=normal,company2,big,deep RUNS=5 BIG_LIMIT=600). Use BULLET=off MINI_PROFILER=off RAILS_LOG_LEVEL=warn."
  task dashboard: :environment do
    abort "The benchmark runs in development only" unless Rails.env.development?

    DashboardBenchmark.new(
      keys: ENV.fetch("SCENARIOS", "normal,company2,big,deep").split(","),
      runs: ENV.fetch("RUNS", 5).to_i,
      big_limit: ENV.fetch("BIG_LIMIT", 600).to_i,
      password: ENV.fetch("SEED_ADMIN_PASSWORD", AssessmentSeeder::DEFAULT_PASSWORD)
    ).call
  end

  desc "EXPLAIN (ANALYZE, BUFFERS) for the dashboard's main query (SCENARIO=normal|company2|big|deep)"
  task explain: :environment do
    abort "Development only" unless Rails.env.development?

    scenario = ENV.fetch("SCENARIO", "big")
    company = Company.find_by!(name: %w[ big deep ].include?(scenario) ? "Company 01" : "Company 02")
    page_size = DashboardController::PAGE_SIZE
    offset = scenario == "deep" ? 2_999 * page_size : 0
    relation = company.assessments.order(assessment_date: :desc, id: :desc).offset(offset).limit(page_size + 1)
    relation = relation.matching(date_from: Date.new(2024, 1, 1), date_to: Date.new(2024, 12, 31), status: nil) if scenario == "normal"
    connection = ActiveRecord::Base.connection
    puts "-- main query (#{scenario})"
    connection.execute("EXPLAIN (ANALYZE, BUFFERS) #{relation.to_sql}").each { |row| puts row["QUERY PLAN"] }
    puts "-- one employee lookup (what the N+1 repeats once per row)"
    connection.execute("EXPLAIN (ANALYZE, BUFFERS) #{Employee.where(id: Employee.minimum(:id)).limit(1).to_sql}").each { |row| puts row["QUERY PLAN"] }
  end
end

namespace :dashboard do
  desc "Print the first 50 dashboard rows (VIEW=default|filtered) as lines with no emails; redirect to a file to keep it (Req 27)"
  task snapshot: :environment do
    abort "Development only" unless Rails.env.development?

    path = ENV["VIEW"] == "filtered" ? "/dashboard?from=2024-01-01&to=2024-12-31" : "/dashboard"
    probe = DashboardProbe.new(email: "admin1@company-1.example.test", password: ENV.fetch("SEED_ADMIN_PASSWORD", AssessmentSeeder::DEFAULT_PASSWORD))
    lines = probe.snapshot(path)
    puts "# dashboard page 1, Company 01, #{path} (employee_id | date | status | score | email hash)"
    puts lines
    puts "# sha256 #{Digest::SHA256.hexdigest(lines.join("\n"))}"
  end
end
