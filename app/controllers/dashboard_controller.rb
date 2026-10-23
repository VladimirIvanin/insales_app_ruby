class DashboardController < ApplicationController
  prepend_before_action :check_tab_context
  before_action :require_session, except: :logout

  def index
  end

  def probe
    session[:probe_requested] = true
    redirect_to account_path(store_id: @context.shop.insales_id), status: :see_other
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

  private
    def check_tab_context
      return unless params[:store_id]
      @context = lifecycle.authenticate(session[:auth_token])
      if @context && params[:store_id].to_s != @context.shop.insales_id.to_s
        render "shared/error", locals: { message: I18n.t("errors.shop_changed") }, status: :conflict
      end
    end
end
