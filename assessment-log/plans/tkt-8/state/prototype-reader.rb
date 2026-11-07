# THROWAWAY prototype of the proposed score contract, to count cases on the 500k seed. Not committed.
KEYS = %w[score assessment_score total_score overall_score].freeze
Outcome = Struct.new(:score, :key, :transforms, :reason, keyword_init: true)

def parse_number(value)
  transforms = []
  case value
  when Integer then number = value
  when Float
    return [ nil, [], :not_finite ] unless value.finite?
    number = value
  when String
    text = value.strip
    match = text.match(/\A(\d+)(?:([.,])(\d+))?(%)?\z/)
    return [ nil, [], :not_numeric ] unless match
    return [ nil, [], :ambiguous_comma ] if match[2] == "," && match[3].length == 3
    transforms << :string_converted
    transforms << :decimal_comma if match[2] == ","
    transforms << :percent_stripped if match[4]
    number = match[3] ? "#{match[1]}.#{match[3]}".to_f : match[1].to_i
  when true, false then return [ nil, [], :boolean ]
  else return [ nil, [], :not_a_number ]
  end
  return [ nil, transforms, :proportion ] if number.positive? && number < 1
  return [ nil, transforms, :out_of_range ] if number.negative? || number > 100
  rounded = number.is_a?(Float) ? number.round(half: :up) : number
  transforms << :rounded if rounded != number
  [ rounded, transforms, nil ]
end

def read_score(candidates)
  first_reason = nil
  KEYS.each_with_index do |key, i|
    value = candidates[i]
    next if value.nil?
    score, transforms, reason = parse_number(value)
    return Outcome.new(score: score, key: key, transforms: transforms) if score
    first_reason ||= reason
  end
  Outcome.new(score: nil, reason: first_reason || :missing)
end

def label(outcome)
  return outcome.reason == :missing ? :missing : (outcome.reason == :proportion ? :proportion_rejected : :other_invalid) unless outcome.score
  return :alias_key if outcome.key != "score"
  return :valid_as_is if outcome.transforms.empty?
  outcome.transforms.first == :string_converted ? (outcome.transforms.include?(:decimal_comma) ? :decimal_comma : (outcome.transforms.include?(:percent_stripped) ? :percent_stripped : :string_converted)) : :rounded
end
