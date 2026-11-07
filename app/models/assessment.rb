class Assessment < ApplicationRecord
  belongs_to :company
  belongs_to :employee

  # status and responses_json are deliberately unvalidated here: they hold ten
  # years of inconsistent legacy values. Later tickets add status rules and the
  # score reader; this scaffold only guarantees the date every assessment has.
  validates :assessment_date, presence: true
end
