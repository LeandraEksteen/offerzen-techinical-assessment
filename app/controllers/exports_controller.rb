class ExportsController < ApplicationController
  before_action :sweep_stale_exports, only: %i[ index create ]

  def index
    @errors = []
    load_page
  end

  # The company comes from the signed-in admin only. Only these three
  # parameters are read; a company_id parameter is never looked at.
  def create
    @filters = ExportFilters.new(current_company, params.permit(:from, :to, :status))
    return render_errors(@filters.errors) unless @filters.valid?

    export = current_company.export_requests.new(
      admin: current_admin, date_from: @filters.date_from, date_to: @filters.date_to, status_filter: @filters.status
    )
    return render_errors(export.errors.full_messages) unless export.save

    ExportJob.perform_later(export)
    redirect_to exports_path, notice: "Export started."
  rescue ActiveRecord::RecordNotUnique
    render_errors([ "An export is already in progress." ])
  end

  # Download. Found through the signed-in admin's company, so another
  # company's export is simply not found.
  def show
    export = current_company.export_requests.find(params[:id])
    raise ActiveRecord::RecordNotFound unless export.downloadable?

    send_data export.file.download, filename: "assessments-export-#{export.id}.csv", type: "text/csv", disposition: "attachment"
  end

  private

  def sweep_stale_exports
    ExportRequest.sweep_stale
  end

  def load_page
    @status_entries = StatusOptions.new(current_company).entries
    @exports = current_company.export_requests.recent
    @any_in_progress = @exports.any?(&:in_progress?)
  end

  def render_errors(messages)
    @errors = messages
    load_page
    render :index, status: :unprocessable_entity
  end
end
