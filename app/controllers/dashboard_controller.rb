# BASELINE for Task 2. This page is deliberately written the way a legacy page
# would be, so the performance work has a real "before" to measure against:
# every matching assessment is loaded and rendered at once (no pagination), and
# the view reads each row's employee through the association (one query per
# row, an N+1). Later tickets fix these one at a time, each with measured numbers.
class DashboardController < ApplicationController
  def show
    @status_entries = StatusOptions.new(current_company).entries
    @filters = ExportFilters.new(current_company, params.permit(:from, :to, :status))
    return render_invalid unless @filters.valid?

    @assessments = current_company.assessments
                                  .matching(date_from: @filters.date_from, date_to: @filters.date_to, status: @filters.status)
                                  .order(assessment_date: :desc, id: :desc)
  end

  private

  def render_invalid
    @errors = @filters.errors
    render :show, status: :unprocessable_entity
  end
end
