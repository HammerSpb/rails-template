class HealthController < ApplicationController
  before_action :authenticate_health_check

  # Deep readiness check: are the app's backing services reachable?
  # Returns 200 when Postgres and Solid Queue both respond, 503 otherwise, so
  # callers (deploy-time verification, external monitoring) can tell a booted
  # app from a fully ready one. Not wired to the Kamal proxy healthcheck —
  # liveness is `/up` (stock Rails health check), which stays shallow.
  def readiness
    checks = {
      app: true,
      database: database_ok?,
      solid_queue: solid_queue_ok?
    }

    payload = {
      status: checks.values.all? ? "ok" : "degraded",
      version: ENV.fetch("APP_VERSION", "dev"),
      git_sha: ENV.fetch("GIT_SHA", "unknown"),
      rails_env: Rails.env,
      checks: checks,
      timestamp: Time.current.iso8601
    }

    render json: payload, status: checks.values.all? ? :ok : :service_unavailable
  end

  private

  # Local requests (deploy host, console curls) skip the token. Remote callers
  # must present a matching `health-check-token` header. Fails closed: an unset
  # HEALTH_CHECK_TOKEN rejects every remote request.
  def authenticate_health_check
    return if request.local?

    expected = ENV["HEALTH_CHECK_TOKEN"].to_s
    provided = request.headers["health-check-token"].to_s

    return if expected.present? &&
              ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    head :unauthorized
  end

  def database_ok?
    ActiveRecord::Base.connection.execute("SELECT 1")
    true
  rescue StandardError
    false
  end

  def solid_queue_ok?
    return true unless defined?(SolidQueue::Process)

    SolidQueue::Process.connection.execute("SELECT 1")
    true
  rescue StandardError
    false
  end
end
