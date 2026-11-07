# Task 3 assessor screen, BASELINE version: one assessment's status edited as free
# text, exactly as the legacy front end let assessors do. Whatever is typed is
# stored as typed, including blank. That is deliberate: it is the "before" half of
# Req 41. The next ticket replaces the field with a validated five-value dropdown.
#
# Tenancy: the assessment is looked up only through the signed-in admin's own
# company, so another company's id is simply not found (404, which also does not
# reveal that the row exists). Only the ids (the required associations check them),
# the date and the status are loaded: the employee's email and the large
# responses_json are never read here.
class AssessmentsController < ApplicationController
  before_action :set_assessment

  def edit
  end

  def update
    @assessment.update!(status: params.expect(assessment: [ :status ])[:status].to_s)
    StatusOptions.forget(current_company)
    redirect_to dashboard_path, notice: "Status saved."
  end

  private

  def set_assessment
    @assessment = current_company.assessments.select(:id, :company_id, :employee_id, :assessment_date, :status).find(params[:id])
  end
end
