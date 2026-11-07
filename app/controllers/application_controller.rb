class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :require_admin

  helper_method :current_admin, :current_company

  private

  # The signed-in admin is the only source of tenancy. Never read a company
  # id from params to decide what a user may see or export.
  def current_admin
    return @current_admin if defined?(@current_admin)

    @current_admin = Admin.find_by(id: session[:admin_id])
  end

  def current_company
    current_admin&.company
  end

  def require_admin
    return if current_admin

    reset_session
    redirect_to new_session_path
  end
end
