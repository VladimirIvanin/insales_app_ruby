class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  before_action :prevent_caching
  rescue_from Insales::Lifecycle::Failure, with: :lifecycle_error
  rescue_from Insales::Protocol::InvalidInput, ActionController::ParameterMissing, with: :invalid_request

  private
    def lifecycle
      @lifecycle ||= Insales::Lifecycle.new(client_factory: Rails.configuration.x.insales_client_factory)
    end

    def prevent_caching
      response.headers["Cache-Control"] = "no-store"
    end

    def lifecycle_error(error)
      response.headers["Retry-After"] = "60" if error.status == 503
      render "shared/error", formats: :html, locals: { message: I18n.t("errors.#{error.code}") }, status: error.status
    end

    def invalid_request
      render "shared/error", formats: :html, locals: { message: I18n.t("errors.invalid_request") }, status: :bad_request
    end

    def require_session
      @context ||= lifecycle.authenticate(session[:auth_token])
      return if @context
      reset_session
      render "shared/error", formats: :html, locals: { message: I18n.t("errors.session_required") }, status: :unauthorized
    end
end
