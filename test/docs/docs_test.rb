require "test_helper"
require "rake"

# Keeps the written deliverables honest: links resolve, the commands they name exist,
# the required sections are there, Future work is not secretly implemented, and the
# seeded development password never ends up in a document.
class DocsTest < ActiveSupport::TestCase
  ROOT = Rails.root
  README = ROOT.join("README.md").read
  SOLUTION = ROOT.join("SOLUTION.md").read
  LINKED_DOCS = %w[ README.md SOLUTION.md assessment-log/README.md assessment-log/DECISIONS.md ].freeze

  # UT-1
  test "every relative markdown link in the main documents points at a file or folder that exists" do
    broken = LINKED_DOCS.flat_map do |doc|
      path = ROOT.join(doc)
      path.read.scan(/\]\(([^)\s]+)\)/).flatten.filter_map do |target|
        next if target.start_with?("http", "#", "mailto:")

        file = path.dirname.join(target.split("#").first)
        "#{doc} -> #{target}" unless file.exist?
      end
    end

    assert_empty broken
  end

  # UT-2
  test "every namespaced rake task named in the README and SOLUTION.md exists" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("assessments:seed")
    named = (README + SOLUTION).scan(/bin\/rails ((?:[a-z_]+:)+[a-z_]+)/).flatten.uniq

    assert_includes named, "assessments:seed"
    assert_includes named, "statuses:report"
    missing = named.reject { |task| Rake::Task.task_defined?(task) }
    assert_empty missing
  end

  # UT-3
  test "SOLUTION.md has the required sections" do
    {
      "Task 1" => /^## Task 1/,
      "Task 2" => /^## Task 2/,
      "Task 3" => /^## Task 3/,
      "the async choice" => /^### Why asynchronous/,
      "the legacy export controls" => /^### The legacy export, control by control/,
      "storage" => /^### Storage/,
      "the benchmarks before and after" => /^### The four changes, one at a time/,
      "the baseline" => /^### The baseline/,
      "the score assumptions" => /^## The score assumptions/,
      "what the score reader assumes" => /^### What the reader assumes/,
      "the masked production copy" => /masked copy of production/,
      "the release and rollback plan" => /^### The seven steps/,
      "the rename and rollback" => /^#### The rename/,
      "Future work" => /^## Future work/
    }.each do |name, pattern|
      assert_match pattern, SOLUTION, "SOLUTION.md is missing #{name}"
    end
  end

  # UT-4
  test "Future work names polling, a done banner, score gating or alerts and measurement, and none of it exists" do
    future = SOLUTION[/^## Future work\n(.*?)(?=^## )/m, 1]

    assert_match(/polling/i, future)
    assert_match(/banner/i, future)
    assert_match(/gating or alerts/i, future)
    assert_match(/staging and production measurement/i, future)

    code = Dir[ROOT.join("{app,lib,config}/**/*.{rb,erb,ts,js,rake}")].reject { |file| file.include?("/builds/") }
    assert_empty code.select { |file| File.read(file, encoding: "UTF-8").match?(/setInterval|done[_-]?banner|export[_-]?ready[_-]?banner|EventSource|ActionCable::Channel/) }.map { |file| file.sub("#{ROOT}/", "") }
  end

  # UT-5
  test "the README covers PGPORT, seeding, the worker and sign-in, and no document holds the seeded password" do
    [ "PGPORT", "assessments:seed", "bin/jobs", "SOLID_QUEUE_IN_PUMA", "SEED_ADMIN_PASSWORD", "AssessmentSeeder::DEFAULT_PASSWORD", "admin1@company-1.example.test", "5433" ].each do |needle|
      assert_includes README, needle
    end

    password = AssessmentSeeder::DEFAULT_PASSWORD
    docs = Dir[ROOT.join("{*.md,assessment-log/**/*.md}")]
    assert docs.size > 20
    leaking = docs.select { |file| File.read(file, encoding: "UTF-8").include?(password) }.map { |file| file.sub("#{ROOT}/", "") }
    assert_empty leaking
  end

  test "the numbers quoted for the headline results match the benchmarks file" do
    benchmarks = ROOT.join("assessment-log/benchmarks/task-2-dashboard.md").read

    [ "58,019", "199,064", "1,414", "2,552", "3,767" ].each do |figure|
      assert_includes SOLUTION, figure
      assert_includes benchmarks, figure, "#{figure} is quoted in SOLUTION.md but is not in the benchmarks file"
    end
  end
end
