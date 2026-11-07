# Reads an assessment's score out of its stored responses_json.
#
# WE DO NOT KNOW WHAT THE REAL DATA LOOKS LIKE. The brief says the displayed score
# is "sometimes blank or obviously off" and never says where the score lives or what
# scale it uses. This reader is an educated guess at ten years of legacy drift. It is
# deliberately small, every rule is a separate unit that can be removed once the real
# data is known (run `bin/rails scores:report` on a masked production copy first),
# and it NEVER rewrites stored data: it only decides what to show.
#
# THE CONTRACT
#   Where:    only the top-level keys score, assessment_score, total_score, overall_score,
#             in that order. The first one holding a VALID value wins. Values are never
#             combined or averaged. A root that is not an object (a JSON string, an array,
#             null) has no keys and gives no score.
#   A number: a JSON number, or a string that is, after trimming, digits with an optional
#             single "." or "," decimal part and an optional "%" (a space before it is
#             allowed): "85", "85%", "85 %", "84,5", "84.5". Anything else is not a number:
#             "N/A", "", "85 out of 100", "1.234,5", booleans, objects, arrays.
#             A comma followed by exactly three digits ("1,234") is AMBIGUOUS (it could be
#             a thousands separator) and is invalid; one or two digits ("84,5") is a
#             decimal comma.
#   Range:    0 to 100 inclusive. Below 0 or above 100 is invalid. A value strictly
#             between 0 and 1 (0.85) is NOT scaled to 85 and is invalid, because it could
#             mean 0.85 or 85; it is counted separately in the report.
#   Rounding: half up, to a whole number (84.5 gives 85, 84.4999 gives 84, 84.99999 gives 85).
#   Result:   a whole number 0 to 100, or nothing. Nothing is shown as "Score not available"
#             on the dashboard and left blank in the CSV. Status never matters.
#
# KNOWN LIMITATION: scales such as 1 to 5 or 0 to 10 cannot be told apart from low
# percentages and are read as percentages.
#
# The four candidate values are read in SQL (see .candidate_sql), so free-text answers
# never reach Ruby and the large responses_json column is not loaded.
class ScoreReader
  # The one list of keys. The SQL, the report and the reader are all generated from it.
  KEYS = %w[ score assessment_score total_score overall_score ].freeze

  # Each rule is a separate, removable unit. Build a reader with fewer rules to see
  # exactly what one of them does (the tests do), and delete a rule with its test once
  # the report shows the real data never needs it.
  DEFAULT_RULES = %i[ scalar_only string_number percent_sign decimal_comma range proportion round_half_up ].freeze

  # score:  whole number 0 to 100, or nil
  # key:    which key it came from (nil when there is no score)
  # rules:  what had to be done to the stored value (:alias_key, :string_number,
  #         :percent_sign, :decimal_comma, :round_half_up); empty when stored cleanly
  # reason: why there is no score (:missing, :not_scalar, :boolean, :not_numeric,
  #         :ambiguous_comma, :out_of_range, :proportion, :error); nil when there is one
  Outcome = Struct.new(:score, :key, :rules, :reason, keyword_init: true)

  NUMBER = /\A(\d+)(?:([.,])(\d+))?\s*(%)?\z/

  # SQL expressions that pull each candidate key out of responses_json. A non-object
  # root (or a missing key) gives NULL.
  def self.candidate_sql
    KEYS.map { |key| "responses_json->'#{key}'" }
  end

  # The same expressions with the alias Assessment.with_score_candidates reads them by.
  def self.candidate_select_sql
    KEYS.each_with_index.map { |key, index| "responses_json->'#{key}' AS score_candidate_#{index}" }
  end

  def self.read(candidates)
    default.read(candidates)
  end

  def self.default
    @default ||= new
  end

  def initialize(rules: DEFAULT_RULES)
    @rules = rules
  end

  # candidates: the value of each key in KEYS order (nil when absent).
  def read(candidates)
    first_reason = nil
    KEYS.each_with_index do |key, index|
      value = Array(candidates)[index]
      next if value.nil?

      number, applied, reason = interpret(value)
      return Outcome.new(score: number, key: key, rules: applied + (key == KEYS.first ? [] : [ :alias_key ]), reason: nil) if number

      first_reason ||= reason
    end
    Outcome.new(score: nil, key: nil, rules: [], reason: first_reason || :missing)
  rescue StandardError
    Outcome.new(score: nil, key: nil, rules: [], reason: :error)
  end

  private

  def enabled?(rule)
    @rules.include?(rule)
  end

  # Returns [number or nil, rules applied, reason when nil].
  def interpret(value)
    applied = []
    number = to_number(value, applied)
    return [ nil, [], number ] if number.is_a?(Symbol)

    return [ nil, applied, :proportion ] if enabled?(:proportion) && number.positive? && number < 1
    return [ nil, applied, :out_of_range ] if enabled?(:range) && (number.negative? || number > 100)

    if enabled?(:round_half_up) && number.is_a?(Float)
      rounded = number.round(half: :up)
      applied << :round_half_up if rounded != number
      number = rounded
    end
    [ number, applied, nil ]
  end

  # A number, or a Symbol naming why the value is not one.
  def to_number(value, applied)
    case value
    when Integer then value
    when Float then value.finite? ? value : :not_numeric
    when String then string_to_number(value, applied)
    when true, false then enabled?(:scalar_only) ? :boolean : :not_numeric
    else enabled?(:scalar_only) ? :not_scalar : :not_numeric
    end
  end

  def string_to_number(text, applied)
    return :not_numeric unless enabled?(:string_number)

    match = NUMBER.match(text.strip)
    return :not_numeric unless match

    integer, separator, fraction, percent = match.captures
    return :not_numeric if percent && !enabled?(:percent_sign)

    if separator == ","
      return :not_numeric unless enabled?(:decimal_comma)
      return :ambiguous_comma if fraction.length == 3
    end

    applied << :string_number
    applied << :percent_sign if percent
    applied << :decimal_comma if separator == ","
    fraction ? "#{integer}.#{fraction}".to_f : integer.to_i
  end
end
