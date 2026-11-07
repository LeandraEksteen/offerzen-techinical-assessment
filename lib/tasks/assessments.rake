namespace :assessments do
  desc "Seed large messy synthetic assessment data (TOTAL=500000 COMPANIES=20). Run on an empty assessments table."
  task seed: :environment do
    AssessmentSeeder.new(
      total: ENV.fetch("TOTAL", 500_000).to_i,
      companies: ENV.fetch("COMPANIES", 20).to_i
    ).call
  end
end
