class Assessment < ApplicationRecord
  include PiiAttributes

  belongs_to :company
  belongs_to :employee
  # For list pages that show only the employee's email (the dashboard). Preloading this
  # loads just id and email in one query for the whole page. Reading any other employee
  # attribute through it raises (ActiveModel::MissingAttributeError) instead of silently
  # running another query; use :employee when you need the rest.
  belongs_to :employee_for_listing, -> { select(:id, :email) }, class_name: "Employee", foreign_key: :employee_id, inverse_of: false

  pii_attributes :employee_email, :responses_json

  # The only statuses a new or changed assessment may hold (Req 29). No alias mapping
  # on write: "Complete", "complete " or "done" are rejected, not translated.
  STATUSES = %w[ pending in_progress completed needs_follow_up archived ].freeze

  validates :assessment_date, presence: true

  # A new assessment with no status (nil) starts as pending (Req 44). An empty string
  # is not "no status": it is one of the legacy dirty values and fails validation.
  before_validation :default_status, on: :create

  # Runs only when the status is being set (a new record or a changed status), so an
  # update to another field of a legacy row that holds a dirty status still succeeds.
  # Before the cut-over date a failure is only counted (no value is logged); on and
  # after it the save fails. Rows written without validations (the seeder, update_all,
  # the later backfill) are legacy or migration paths and are not checked here.
  validate :status_is_canonical, if: :status_being_set?

  @would_be_rejections = Concurrent::AtomicFixnum.new(0)

  class << self
    # How many saves this process let through that the rule will reject from the cut-over
    # date on. Per process and reset on restart: an indication, not an audit.
    def would_be_rejections
      @would_be_rejections.value
    end

    # From the cut-over date (inclusive) on, or always when no date is configured.
    def status_rule_enforced?(today = Date.current)
      cutover = Rails.configuration.x.status_cutover_date
      cutover.nil? || today >= cutover
    end

    def record_would_be_rejection
      count = @would_be_rejections.increment
      Rails.logger.info "status validation: would reject after cut-over (count=#{count})"
    end
  end

  # Adds the score's candidate keys (see ScoreReader) to the select, read in SQL so the
  # free-text answers in responses_json never reach Ruby and the large column is not loaded.
  # Combine with the columns the page needs: select(:id, ...).with_score_candidates.
  scope :with_score_candidates, lambda {
    select(*ScoreReader.candidate_select_sql.map { |sql| Arel.sql(sql) })
  }

  # What to show for this assessment's score. Needs the record to have been loaded
  # with_score_candidates.
  def score_outcome
    ScoreReader.read(ScoreReader::KEYS.each_index.map { |index| self["score_candidate_#{index}"] })
  end

  # The two filters shared by the export and the dashboard, in one place so the
  # two can never disagree: an inclusive assessment date range (either end may
  # be nil) and a status value from StatusOptions (nil means all).
  def self.matching(date_from:, date_to:, status:)
    scope = all
    scope = scope.where("assessments.assessment_date >= ?", date_from) if date_from
    scope = scope.where("assessments.assessment_date <= ?", date_to) if date_to
    scope = scope.where(*Array(StatusOptions.condition(status))) if status
    scope
  end

  private

  def default_status
    self.status = "pending" if status.nil?
  end

  def status_being_set?
    new_record? || will_save_change_to_status?
  end

  def status_is_canonical
    return if STATUSES.include?(status)

    if self.class.status_rule_enforced?
      errors.add(:status, "must be one of: #{STATUSES.join(', ')}")
    else
      self.class.record_would_be_rejection
    end
  end
end
