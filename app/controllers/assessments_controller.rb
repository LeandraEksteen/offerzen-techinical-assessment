# Task 3 assessor screen, VALIDATED version (Req 41): one assessment's status chosen
# from the five canonical values. The earlier free-text version (TKT-9) is in git
# history as the "before".
#
# The dropdown is live from the day it ships, so this screen refuses anything but the
# five values (empty included) whatever the cut-over date is. The date only decides
# whether OTHER writers are rejected by the model (see Assessment).
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
    status = params.expect(assessment: [ :status ])[:status].to_s
    unless Assessment::STATUSES.include?(status)
      @error = "Choose one of the listed statuses."
      return render :edit, status: :unprocessable_entity
    end

    @assessment.update!(status: status)
    StatusOptions.forget(current_company)
    redirect_to dashboard_path, notice: "Status saved."
  end

  private

  def set_assessment
    @assessment = current_company.assessments.select(:id, :company_id, :employee_id, :assessment_date, :status).find(params[:id])
  end
end
