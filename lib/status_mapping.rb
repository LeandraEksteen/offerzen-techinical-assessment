# The versioned mapping from stored legacy statuses to the five canonical ones
# (db/status_mapping.yml). It is the only input the historical backfill would use, and
# it is a PLAN: nothing in this repository applies it. Today only StatusReport reads it,
# to show what a mapping would do.
#
# Keys are NORMALISED stored values: trimmed (space, tab, CR, LF), lower-cased, the same
# way StatusOptions groups them, with "__none__" standing for NULL, empty and blank-only.
# A value with no entry is unmapped: it would stay NULL in the new column and block the
# switch. The file stays a draft (approved: false) until assessors have confirmed it.
class StatusMapping
  class Invalid < StandardError; end

  PATH = Rails.root.join("db/status_mapping.yml")
  NONE = "__none__".freeze
  TRIM = " \t\r\n".freeze

  # The file at PATH, or nil when there is none.
  def self.load(path = PATH)
    return nil unless File.exist?(path)

    new(YAML.safe_load_file(path))
  end

  # nil, empty and blank-only all become NONE; anything else is trimmed and lower-cased.
  def self.normalise(value)
    text = value.to_s.gsub(/\A[#{Regexp.escape(TRIM)}]+|[#{Regexp.escape(TRIM)}]+\z/, "").downcase
    text.empty? ? NONE : text
  end

  attr_reader :version, :approved_by, :approved_on

  def initialize(data)
    data = {} unless data.is_a?(Hash)
    @version = data["version"]
    @approved = data["approved"]
    @approved_by = data["approved_by"]
    @approved_on = data["approved_on"]
    @entries = data["mapping"]
    validate!
  end

  def approved?
    @approved == true
  end

  def draft?
    !approved?
  end

  # The canonical status a stored value maps to, or nil when it is unmapped.
  def target_for(stored_value)
    @entries[self.class.normalise(stored_value)]
  end

  private

  def validate!
    raise Invalid, "version must be a whole number" unless @version.is_a?(Integer)
    raise Invalid, "approved must be true or false" unless [ true, false ].include?(@approved)
    raise Invalid, "mapping must be a list of stored value: canonical status" unless @entries.is_a?(Hash)
    raise Invalid, "an approved mapping needs approved_by and approved_on" if approved? && (@approved_by.blank? || @approved_on.blank?)

    @entries.each do |key, target|
      raise Invalid, "key #{key.inspect} is not normalised (trimmed and lower-case)" unless key.is_a?(String) && key == self.class.normalise(key)
      raise Invalid, "#{key.inspect} maps to #{target.inspect}, which is not one of #{Assessment::STATUSES.join(', ')}" unless Assessment::STATUSES.include?(target)
    end
  end
end
