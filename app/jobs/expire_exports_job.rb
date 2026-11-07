# Removes the files of exports past their retention period and marks them
# expired. The history already shows such exports as expired and refuses their
# download; this job only frees the storage. Scheduled in config/recurring.yml.
class ExpireExportsJob < ApplicationJob
  queue_as :default

  def perform
    ExportRequest.where.not(state: "expired").where(created_at: ..ExportRequest::RETENTION.ago).find_each do |export|
      export.file.purge if export.file.attached?
      export.update_columns(state: "expired", updated_at: Time.current)
    end
  end
end
