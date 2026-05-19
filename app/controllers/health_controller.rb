class HealthController < ApplicationController
  def show
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
