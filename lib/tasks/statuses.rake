namespace :statuses do
  desc "Read-only report: distinct stored statuses with row count and latest updated_at, and what db/status_mapping.yml would do (BATCH=10000)"
  task report: :environment do
    StatusReport.new(batch: ENV.fetch("BATCH", StatusReport::BATCH).to_i).call
  end
end
