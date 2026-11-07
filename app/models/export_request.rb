class ExportRequest < ApplicationRecord
  # An export still "in progress" after this long is treated as failed, so a
  # job that died cannot block its admin forever.
  STALE_AFTER = 30.minutes
  # Exports (and their files) are kept for a week.
  RETENTION = 7.days
  HISTORY_SIZE = 20

  belongs_to :company
  belongs_to :admin
  has_one_attached :file

  enum :state, { in_progress: "in_progress", ready: "ready", failed: "failed", expired: "expired" }

  validate :admin_has_no_export_in_progress, on: :create

  scope :recent, -> { order(created_at: :desc, id: :desc).limit(HISTORY_SIZE) }

  def self.sweep_stale
    in_progress.where(created_at: ..STALE_AFTER.ago)
               .update_all(state: "failed", finished_at: Time.current, updated_at: Time.current)
  end

  def past_retention?
    created_at < RETENTION.ago
  end

  # What the history table shows: an export older than the retention period is
  # expired whether or not the purge job has run yet.
  def shown_state
    past_retention? ? "expired" : state
  end

  def downloadable?
    ready? && !past_retention? && file.attached?
  end

  private

  def admin_has_no_export_in_progress
    return unless in_progress? && self.class.in_progress.where(admin_id: admin_id).exists?

    errors.add(:base, "An export is already in progress.")
  end
end
