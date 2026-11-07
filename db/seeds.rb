# Small, fast seed: bin/ci runs db:seed:replant in the test environment, so
# this must stay quick. For the large messy dataset used by the later tickets
# run `bin/rails assessments:seed` (about 500,000 rows) instead.
unless Assessment.exists?
  AssessmentSeeder.new(total: 300, companies: 3, output: StringIO.new).call
end
