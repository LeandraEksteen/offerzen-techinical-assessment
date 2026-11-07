# The statuses a company has actually stored, for the status filter.
#
# Legacy statuses are messy ("Complete", "complete ", "COMPLETE", nil, ""...).
# This groups them by trimmed, lowercased value WITHOUT changing any stored
# data. nil, empty and blank-only all become one "no status" entry. It does not
# merge spellings (comp, done): that is the status normalisation work (Task 3).
class StatusOptions
  CACHE_TTL = 10.minutes
  # Form value that means "no status".
  NONE = "__none__".freeze
  NONE_LABEL = "(no status)".freeze

  # The single place that names the status column in raw SQL: trimmed,
  # lowercased, and NULL when nothing is left.
  NORMALISED_SQL = "NULLIF(lower(btrim(status, E' \\t\\r\\n')), '')".freeze

  def initialize(company)
    @company = company
  end

  # Entries for a select, as [label, value]: the statuses, then "no status".
  def entries
    present = cached.compact.sort.map { |status| [ status, status ] }
    cached.include?(nil) ? present + [ [ NONE_LABEL, NONE ] ] : present
  end

  # A submitted value is valid if the company has it. If the cached list does
  # not have it, re-read once uncached before saying no (it may be brand new).
  def valid?(value)
    return true if allows?(cached, value)

    allows?(read, value)
  end

  # Forget a company's cached list, so a status saved just now shows in the filter at once.
  def self.forget(company)
    Rails.cache.delete(cache_key(company))
  end

  def self.cache_key(company)
    "status_options/v1/company/#{company.id}"
  end

  # SQL condition (and bind) selecting the rows a submitted value stands for.
  def self.condition(value)
    value == NONE ? "#{NORMALISED_SQL} IS NULL" : [ "#{NORMALISED_SQL} = ?", value ]
  end

  private

  def allows?(list, value)
    value == NONE ? list.include?(nil) : list.include?(value)
  end

  def cached
    Rails.cache.fetch(self.class.cache_key(@company), expires_in: CACHE_TTL) { read }
  end

  def read
    @company.assessments.distinct.pluck(Arel.sql(NORMALISED_SQL))
  end
end
