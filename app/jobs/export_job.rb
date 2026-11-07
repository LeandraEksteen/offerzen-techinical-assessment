# Builds an export's CSV in the background. Takes the ExportRequest record
# (never filters or personal data, see ApplicationJob).
class ExportJob < ApplicationJob
  queue_as :default

  # An export is not retried: the admin can start a new one.
  discard_on ActiveJob::DeserializationError

  def perform(export_request)
    return unless export_request.in_progress?

    Tempfile.create([ "assessments-export-", ".csv" ]) do |file|
      count = AssessmentCsvExport.new(export_request).write_to(file)
      file.rewind
      export_request.file.attach(io: file, filename: "assessments-export-#{export_request.id}.csv", content_type: "text/csv")
      export_request.update!(state: :ready, row_count: count, finished_at: Time.current)
    end
  rescue StandardError => error
    # Log only the class and the export id: error messages can quote data.
    Rails.logger.error("ExportJob failed export=#{export_request&.id} error=#{error.class}")
    export_request&.update_columns(state: "failed", finished_at: Time.current, updated_at: Time.current)
  end
end
