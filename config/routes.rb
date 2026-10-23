Rails.application.routes.draw do
  get "/healthz", to: "rails/health#show"
  get "/install", to: "connections#install"
  get "/login", to: "connections#login"
  get "/auth/callback", to: "connections#callback"
  get "/uninstall", to: "connections#uninstall"
  root "dashboard#index"
  post "/probe", to: "dashboard#probe"
  get "/account", to: "dashboard#account"
  post "/logout", to: "dashboard#logout"
end
