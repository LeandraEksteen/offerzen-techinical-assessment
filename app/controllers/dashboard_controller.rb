# Task 2 dashboard. It started as a deliberately legacy-style BASELINE so the
# performance work had a real "before" to measure against. Each later ticket
# fixes one thing, with measured numbers (assessment-log/benchmarks):
#   - pagination: 50 rows per page, Previous and Next only
#   - eager loading (this change): the page's employees come in one query (id and
#     email only) instead of one query per row
#   - still the baseline until their tickets: the score is shown exactly as stored,
#     and without an index the database scans the whole company for each page.
class DashboardController < ApplicationController
  PAGE_SIZE = 50
  # Anything that is not a whole number from 1 to this limit shows page 1. The limit
  # also keeps the offset inside what PostgreSQL accepts.
  MAX_PAGE = 1_000_000

  def show
    @status_entries = StatusOptions.new(current_company).entries
    @filters = ExportFilters.new(current_company, params.permit(:from, :to, :status))
    return render_invalid unless @filters.valid?

    @page = page_number
    # Fetch one row more than the page holds: it is never shown, it only tells
    # us a next page exists. That avoids a total count, which would cost a full
    # scan of a large company.
    rows = current_company.assessments
                          .matching(date_from: @filters.date_from, date_to: @filters.date_to, status: @filters.status)
                          .order(assessment_date: :desc, id: :desc)
                          .preload(:employee_for_listing)
                          .offset((@page - 1) * PAGE_SIZE)
                          .limit(PAGE_SIZE + 1)
                          .to_a
    @has_next = rows.size > PAGE_SIZE
    @assessments = rows.first(PAGE_SIZE)
  end

  private

  def page_number
    value = params[:page].to_s
    value.match?(/\A[1-9]\d{0,6}\z/) && value.to_i <= MAX_PAGE ? value.to_i : 1
  end

  def render_invalid
    @errors = @filters.errors
    render :show, status: :unprocessable_entity
  end
end
