Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Liveness — the Rails process booted and is answering. Polled continuously
  # by Kamal's proxy. Deliberately shallow (stock Rails health check): no
  # dependency checks, so a transient database blip can't make the proxy pull
  # an otherwise-healthy container.
  get "up" => "rails/health#show", as: :rails_health_check

  # Readiness — deep dependency check (Postgres + Solid Queue). Token-gated for
  # non-local requests. Intended for deploy-time verification and external
  # monitoring, NOT for the proxy's continuous healthcheck.
  get "readyz" => "health#readiness", as: :readiness_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
