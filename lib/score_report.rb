# Read-only report on how ScoreReader reads the stored scores: how many rows fall
# into each case, which rules were needed, and a few examples of each case. It
# never writes anything. Run it on a masked copy of production data before trusting
# the reader's rules, and delete rules the real data never needs.
#
#   bin/rails scores:report
#
# A raw score token could be free text typed into the score key (even a short word can
# be a name), so a token is only printed when it is made of digits and number
# punctuation, or is one of a few placeholder words such as "N/A"; anything else is
# described by its length, never shown.
class ScoreReport
  BATCH = 10_000
  EXAMPLES = 5
  CASES = %i[ valid_as_is string_converted percent_stripped decimal_comma rounded alias_key proportion_rejected other_invalid missing ].freeze
  SAFE_NUMBER_TOKEN = /\A[0-9.,%\s-]{0,20}\z/
  PLACEHOLDER_WORDS = %w[ n/a na none null nil tbd unknown ].freeze

  def initialize(output: $stdout, batch: BATCH)
    @output = output
    @batch = batch
  end

  def call
    counts = Hash.new(0)
    examples = Hash.new { |hash, key| hash[key] = [] }
    rules = Hash.new(0)
    reasons = Hash.new(0)
    non_object_roots = 0
    total = 0

    each_row do |id, candidates, root_type|
      outcome = ScoreReader.read(candidates)
      kind = classify(outcome)
      counts[kind] += 1
      total += 1
      outcome.rules.each { |rule| rules[rule] += 1 }
      reasons[outcome.reason] += 1 if outcome.reason
      non_object_roots += 1 if kind == :missing && root_type != "object"
      examples[kind] << [ id, safe_token(candidates), outcome.score || outcome.reason ] if examples[kind].size < EXAMPLES
    end

    print_report(total, counts, examples, rules, reasons, non_object_roots)
  end

  private

  def each_row
    last_id = 0
    expressions = ScoreReader.candidate_sql.map { |sql| Arel.sql(sql) } + [ Arel.sql("jsonb_typeof(responses_json)") ]
    loop do
      rows = Assessment.where("id > ?", last_id).order(:id).limit(@batch).pluck(:id, *expressions)
      break if rows.empty?

      rows.each { |id, *rest| yield id, rest.first(ScoreReader::KEYS.size), rest.last }
      last_id = rows.last.first
    end
  end

  def classify(outcome)
    return :missing if outcome.reason == :missing
    return :proportion_rejected if outcome.reason == :proportion
    return :other_invalid if outcome.reason

    rules = outcome.rules
    return :alias_key if rules.include?(:alias_key)
    return :decimal_comma if rules.include?(:decimal_comma)
    return :percent_stripped if rules.include?(:percent_sign)
    return :string_converted if rules.include?(:string_number)
    return :rounded if rules.include?(:round_half_up)

    :valid_as_is
  end

  # The raw value of the first candidate key that is present, made safe to print.
  def safe_token(candidates)
    value = candidates.compact.first
    return "(no score key)" if value.nil?
    return "[#{value.class.name.downcase}]" if value.is_a?(Hash) || value.is_a?(Array)

    text = value.to_s
    printable = text.match?(SAFE_NUMBER_TOKEN) || PLACEHOLDER_WORDS.include?(text.strip.downcase)
    printable ? Pii::Scrubber.scrub_text(text) : "[text, #{text.length} characters]"
  end

  def print_report(total, counts, examples, rules, reasons, non_object_roots)
    @output.puts "Score report: #{total} assessments (read only; nothing is written)"
    @output.puts
    @output.puts "Cases (one per row; the first that applies):"
    CASES.each do |kind|
      suffix = kind == :missing ? " (of which the root is not an object: #{non_object_roots})" : ""
      @output.puts format("  %-20s %9d  %5.1f%%%s", kind, counts[kind], total.zero? ? 0 : counts[kind] * 100.0 / total, suffix)
    end
    shown = total - counts[:missing] - counts[:proportion_rejected] - counts[:other_invalid]
    @output.puts format("  %-20s %9d  %5.1f%%", "shown with a score", shown, total.zero? ? 0 : shown * 100.0 / total)
    @output.puts
    @output.puts "Rules applied (rows each rule was needed for; delete a rule the real data never needs):"
    %i[ alias_key string_number percent_sign decimal_comma round_half_up ].each { |rule| @output.puts format("  %-20s %9d", rule, rules[rule]) }
    @output.puts
    @output.puts "Reasons for no score:"
    reasons.sort_by { |_, count| -count }.each { |reason, count| @output.puts format("  %-20s %9d", reason, count) }
    @output.puts
    @output.puts "Examples (assessment id | raw token | result; tokens that are not numbers or a placeholder word such as N/A are described, never printed):"
    CASES.each do |kind|
      next if examples[kind].empty?

      @output.puts "  #{kind}"
      examples[kind].each { |id, token, result| @output.puts "    #{id} | #{token} | #{result}" }
    end
  end
end
