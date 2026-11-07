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

  # status and responses_json are deliberately unvalidated here: they hold ten
  # years of inconsistent legacy values. Later tickets add status rules and the
  # score reader; this scaffold only guarantees the date every assessment has.
  validates :assessment_date, presence: true

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
end
