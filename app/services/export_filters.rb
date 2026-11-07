# The two export filters: an assessment date range and a status.
# Validates user input; never reads a company from it.
class ExportFilters
  attr_reader :date_from, :date_to, :status, :errors

  def initialize(company, params)
    @company = company
    @errors = []
    @date_from = parse_date(params[:from], "Start date")
    @date_to = parse_date(params[:to], "End date")
    @status = params[:status].presence
    validate
  end

  def valid?
    errors.empty?
  end

  private

  def parse_date(value, label)
    return nil if value.blank?

    Date.iso8601(value.to_s)
  rescue Date::Error
    @errors << "#{label} is not a valid date."
    nil
  end

  def validate
    errors << "Start date is after the end date." if date_from && date_to && date_from > date_to
    errors << "That status is not one of your statuses." if status && !StatusOptions.new(@company).valid?(status)
  end
end
