class ConnectionsController < ApplicationController
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new(size: 2.megabytes)
  rate_limit to: 60, within: 1.minute, only: %i[install login], name: "ip", store: RATE_LIMIT_STORE, with: :rate_limited
  rate_limit to: 30, within: 1.minute, only: %i[install login], name: "shop", store: RATE_LIMIT_STORE,
    by: -> { params[:shop].to_s.downcase.byteslice(0, 253) }, with: :rate_limited
  before_action { response.headers["Referrer-Policy"] = "no-referrer" }

  def install
    lifecycle.install(shop: params.expect(:shop), insales_id: params.expect(:insales_id), token: params.expect(:token))
    render plain: "ok"
  end

  def login
    session[:browser_token] ||= SecureRandom.hex(32)
    result = lifecycle.begin_login(shop: params.expect(:shop), insales_id: params.expect(:insales_id),
      browser_token: session[:browser_token])
    session[:challenge_id] = result.challenge.id
    redirect_to result.redirect_url, allow_other_host: true
  end

  def callback
    unless session[:challenge_id] && session[:browser_token]
      raise Insales::Lifecycle::Failure.new(:invalid_challenge, 403)
    end
    grant = lifecycle.complete_login(challenge_id: session[:challenge_id], browser_token: session[:browser_token],
      token3: params.expect(:token3), user_email: params.expect(:user_email), user_name: params.fetch(:user_name, ""),
      user_id: params.expect(:user_id), email_confirmed: params.expect(:email_confirmed))
    lifecycle.logout(session[:auth_token])
    reset_session
    session[:auth_token] = grant.token
    redirect_to root_path, status: :see_other
  end

  def uninstall
    lifecycle.uninstall(shop: params.expect(:shop), insales_id: params.expect(:insales_id), token: params.expect(:token))
    render plain: "ok"
  end

  private
    def rate_limited
      response.headers["Retry-After"] = "60"
      raise Insales::Lifecycle::Failure.new(:rate_limited, 429)
    end
end
