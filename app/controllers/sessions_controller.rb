class SessionsController < ApplicationController
  skip_before_action :require_admin, only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Too many attempts. Try again later." }

  def new
  end

  def create
    admin = Admin.find_by(email: Admin.normalize_value_for(:email, params[:email].to_s))

    if admin&.authenticate(params[:password].to_s)
      reset_session
      session[:admin_id] = admin.id
      redirect_to root_path
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to new_session_path, status: :see_other
  end
end
