class DashboardController < ApplicationController
  before_action :require_session, except: :logout

  def index
  end

  def probe
    session[:probe_requested] = true
    redirect_to account_path, status: :see_other
  end

  def account
    return redirect_to root_path unless session.delete(:probe_requested)
    @account = lifecycle.client(@context.shop).account
    raise Insales::ResourceError, "Account identity mismatch" unless @account.data.fetch("id") == @context.shop.insales_id
    render :index
  rescue Insales::Error
    render "shared/error", locals: { message: I18n.t("errors.api_unavailable") }, status: :bad_gateway
  end

  def logout
    lifecycle.logout(session[:auth_token])
    reset_session
    render "shared/message", locals: { message: I18n.t("dashboard.logged_out") }
  end
end
