# Generates deliberately MESSY legacy-style data so later tickets (export,
# dashboard, score reader, status normalisation) have something realistic to
# work against. Everything is synthetic: fake names, reserved example domains,
# placeholder phone numbers. Deterministic for a given seed value.
#
# Usage:
#   AssessmentSeeder.new(total: 500_000, companies: 20).call
#   bin/rails assessments:seed TOTAL=500000 COMPANIES=20
class AssessmentSeeder
  # [stored status, weight]. Covers the legacy variants named in the brief,
  # plus case and whitespace variants. Weights are relative, not percentages.
  STATUS_VARIANTS = [
    [ nil, 3 ], [ "", 3 ], [ " ", 1 ], [ "n/a", 2 ],
    [ "complete", 10 ], [ "Complete ", 3 ], [ "COMPLETE", 2 ], [ "comp", 5 ], [ "done", 5 ], [ "Done", 2 ],
    [ "pending", 15 ], [ "in_progress", 15 ], [ "needs_follow_up", 8 ], [ "archived", 10 ]
  ].freeze

  # [shape name, weight]. How the score may be stored (or not) inside
  # responses_json. These are guesses at ten years of legacy drift; the real
  # shape is unknown. See build_responses for how each is produced.
  SCORE_SHAPES = [
    [ :integer, 50 ], [ :float, 5 ], [ :float_noise, 3 ], [ :string_number, 5 ], [ :string_percent, 3 ],
    [ :decimal_comma, 2 ], [ :alias_assessment_score, 3 ], [ :alias_total_score, 2 ], [ :alias_overall_score, 1 ],
    [ :multiple_keys, 2 ], [ :proportion, 3 ], [ :out_of_range_high, 1.5 ], [ :out_of_range_negative, 0.5 ],
    [ :na_text, 2 ], [ :empty_string, 1 ], [ :null_score, 2 ], [ :missing_key, 6 ],
    [ :double_encoded, 1 ], [ :array_root, 0.5 ], [ :null_root, 0.5 ]
  ].freeze

  FIRST_NAMES = %w[ Alex Sam Jordan Taylor Morgan Casey Riley Jamie Robin Avery ].freeze
  LAST_NAMES = %w[ Example Sample Placeholder Testcase Mockson Faux Demo Dummy Trial Pilot ].freeze

  # Synthetic free text with placeholder personal details, so redaction work
  # has something to catch. None of these refer to real people or numbers.
  COMMENTS = [
    "Chair too low, call Alex Example on 555-0100 to reschedule.",
    "Employee reports wrist pain, contact sam.sample@example.test.",
    "Monitor glare. Follow up with Jordan Placeholder.",
    "No issues reported.",
    "Standing desk requested, ext 555-0123.",
    ""
  ].freeze

  DEFAULT_PASSWORD = "dev-only-password".freeze
  # Assessments per employee: a yearly assessment over ten years.
  EMPLOYEE_RATIO = 10

  def initialize(total:, companies: 20, big_share: 0.4, seed: 42, batch_size: 5_000, output: $stdout)
    @total = total
    @company_count = companies
    @big_share = big_share
    @random = Random.new(seed)
    @batch_size = batch_size
    @output = output
  end

  def call
    raise "Refusing to seed synthetic data in production" if Rails.env.production?
    raise "Assessments already exist; run db:reset first" if Assessment.exists?

    quietly do
      companies = ensure_companies
      ensure_admins(companies)
      plan = allocations(companies)
      employees = ensure_employees(companies, plan)
      insert_assessments(plan, employees)
    end
  end

  private

  # Bulk inserts log their full SQL, including every email and response body.
  # Synthetic or not, we do not want data values in logs, so keep the SQL out.
  def quietly(&block)
    logger = ActiveRecord::Base.logger
    logger ? logger.silence(Logger::WARN, &block) : yield
  end

  def ensure_companies
    (1..@company_count).map { |n| Company.find_or_create_by!(name: "Company #{format('%02d', n)}") }
  end

  def ensure_admins(companies)
    password = ENV.fetch("SEED_ADMIN_PASSWORD", DEFAULT_PASSWORD)
    companies.each_with_index do |company, index|
      Admin.find_or_create_by!(email: "admin#{index + 1}@company-#{index + 1}.example.test") do |admin|
        admin.company = company
        admin.password = password
      end
    end
  end

  # About one employee per ten assessments (a yearly assessment over ten years),
  # so a company's page does not show the same few employees over and over.
  def ensure_employees(companies, plan)
    rows = []
    companies.each_with_index do |company, index|
      count = [ (plan.fetch(company.id) / EMPLOYEE_RATIO.to_f).ceil, 5 ].max
      count.times do |n|
        first = FIRST_NAMES[@random.rand(FIRST_NAMES.size)]
        last = LAST_NAMES[@random.rand(LAST_NAMES.size)]
        rows << { company_id: company.id, name: "#{first} #{last}",
                  email: "#{first}.#{last}#{n}@company-#{index + 1}.example.test".downcase,
                  created_at: Time.current, updated_at: Time.current }
      end
    end
    Employee.insert_all(rows)
    Employee.where(company_id: companies.map(&:id)).pluck(:company_id, :id, :email)
            .group_by(&:first).transform_values { |list| list.map { |_, id, email| [ id, email ] } }
  end

  def allocations(companies)
    big = (@total * @big_share).round
    rest = @total - big
    others = companies.size - 1
    return { companies.first.id => @total } if others.zero?

    per_company, remainder = rest.divmod(others)
    companies.each_with_index.to_h do |company, index|
      next [ company.id, big ] if index.zero?

      [ company.id, per_company + (index <= remainder ? 1 : 0) ]
    end
  end

  def insert_assessments(plan, employees)
    queue = plan.flat_map { |company_id, count| Array.new(count, company_id) }.shuffle(random: @random)
    inserted = 0
    queue.each_slice(@batch_size).with_index do |slice, batch_index|
      rows = slice.each_with_index.map do |company_id, offset|
        build_row(company_id, employees.fetch(company_id), batch_index * @batch_size + offset)
      end
      Assessment.insert_all(rows)
      inserted += rows.size
      @output.puts "  inserted #{inserted} / #{@total}" if (batch_index % 10).zero? || inserted == @total
    end
  end

  # The first rows cycle through every status variant and score shape, so even
  # a small seed contains every case. After that, choices are weighted random.
  def build_row(company_id, employee_pool, index)
    employee_id, employee_email = employee_pool[@random.rand(employee_pool.size)]
    date = Date.current - @random.rand(-60..3650)
    created = [ (date - @random.rand(1..14)).in_time_zone("UTC") + 9.hours, Time.current ].min
    updated = [ created + @random.rand(0..30).days, Time.current ].min
    status = index < STATUS_VARIANTS.size ? STATUS_VARIANTS[index].first : weighted(STATUS_VARIANTS)
    shape = index < SCORE_SHAPES.size ? SCORE_SHAPES[index].first : weighted(SCORE_SHAPES)

    { company_id: company_id, employee_id: employee_id, employee_email: employee_email,
      status: status, responses_json: build_responses(shape), assessment_date: date,
      created_at: created, updated_at: updated }
  end

  def weighted(pairs)
    total = pairs.sum { |_, weight| weight }
    pick = @random.rand * total
    pairs.each do |value, weight|
      pick -= weight
      return value if pick <= 0
    end
    pairs.last.first
  end

  def build_responses(shape)
    answers = Array.new(6) { |n| { "question" => "q#{n + 1}", "value" => @random.rand(1..5) } }
    score = (answers.sum { |a| a["value"] } / answers.size.to_f * 20).round
    base = { "answers" => answers, "comments" => COMMENTS[@random.rand(COMMENTS.size)] }

    case shape
    when :integer then base.merge("score" => score)
    when :float then base.merge("score" => score + 0.5)
    when :float_noise then base.merge("score" => score - 0.00001)
    when :string_number then base.merge("score" => score.to_s)
    when :string_percent then base.merge("score" => "#{score}%")
    when :decimal_comma then base.merge("score" => "#{score},5")
    when :alias_assessment_score then base.merge("assessment_score" => score)
    when :alias_total_score then base.merge("total_score" => score)
    when :alias_overall_score then base.merge("overall_score" => score)
    when :multiple_keys then base.merge("score" => score, "assessment_score" => [ score - 10, 0 ].max)
    when :proportion then base.merge("score" => (score / 100.0).round(2))
    when :out_of_range_high then base.merge("score" => 150)
    when :out_of_range_negative then base.merge("score" => -5)
    when :na_text then base.merge("score" => "N/A")
    when :empty_string then base.merge("score" => "")
    when :null_score then base.merge("score" => nil)
    when :missing_key then base
    when :double_encoded then base.merge("score" => score).to_json
    when :array_root then [ score ]
    when :null_root then nil
    end
  end
end
