settings = Insales::Settings.new(ENV)
Rails.application.config.x.insales = settings
Rails.application.config.active_record.encryption.primary_key = settings.primary_key
Rails.application.config.active_record.encryption.key_derivation_salt = settings.key_salt
Rails.application.config.session_store :cookie_store,
  key: URI(settings.base_url).scheme == "https" ? "__Host-insales_session" : "_insales_session",
  secure: URI(settings.base_url).scheme == "https",
  httponly: true, same_site: :lax, expire_after: 1.hour
Rails.application.config.filter_parameters += %i[token token2 token3 nonce password api_password secret authorization user_email user_name]
Rails.application.config.action_dispatch.default_headers.merge!(
  "Referrer-Policy" => "same-origin",
  "Content-Security-Policy" => "default-src 'none'; style-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
)
