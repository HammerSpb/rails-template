require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  # --- Liveness: /up -------------------------------------------------------

  test "up returns 200 (liveness, process is answering)" do
    get rails_health_check_url
    assert_response :success
  end

  test "up stays 200 even when the database is unreachable" do
    # Liveness must not depend on Postgres — a database blip should not make
    # Kamal's proxy pull an otherwise-healthy container.
    with_database_outage do
      get rails_health_check_url
    end
    assert_response :success
  end

  # --- Readiness: /readyz --------------------------------------------------

  test "readyz returns 200 and status ok when dependencies are reachable" do
    get readiness_check_url
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "ok", body["status"]
    assert_equal true, body.dig("checks", "database")
    assert_equal true, body.dig("checks", "solid_queue")
  end

  test "readyz returns 503 and flags the failing dependency when the database is down" do
    with_database_outage do
      get readiness_check_url
    end
    assert_response :service_unavailable

    body = JSON.parse(response.body)
    assert_equal "degraded", body["status"]
    assert_equal false, body.dig("checks", "database")
  end

  # --- Readiness access control -------------------------------------------

  test "readyz rejects a non-local request with no token" do
    get readiness_check_url, headers: { "REMOTE_ADDR" => "203.0.113.10" }
    assert_response :unauthorized
  end

  test "readyz rejects a non-local request with a wrong token" do
    with_health_token("right-token") do
      get readiness_check_url, headers: {
        "REMOTE_ADDR" => "203.0.113.10",
        "health-check-token" => "wrong-token"
      }
    end
    assert_response :unauthorized
  end

  test "readyz accepts a non-local request carrying the correct token" do
    with_health_token("right-token") do
      get readiness_check_url, headers: {
        "REMOTE_ADDR" => "203.0.113.10",
        "health-check-token" => "right-token"
      }
    end
    assert_response :success
  end

  test "readyz accepts a local request without a token" do
    # Default integration request comes from 127.0.0.1 -> request.local?
    get readiness_check_url
    assert_response :success
  end

  private

  def with_health_token(value)
    previous = ENV["HEALTH_CHECK_TOKEN"]
    ENV["HEALTH_CHECK_TOKEN"] = value
    yield
  ensure
    ENV["HEALTH_CHECK_TOKEN"] = previous
  end

  # Simulate an unreachable database by making `SELECT 1` raise on the
  # connection, while leaving every other query untouched.
  def with_database_outage
    connection = ActiveRecord::Base.connection
    real_execute = connection.method(:execute)
    connection.define_singleton_method(:execute) do |sql, *args, **kwargs|
      raise ActiveRecord::StatementInvalid, "simulated outage" if sql.to_s.include?("SELECT 1")

      real_execute.call(sql, *args, **kwargs)
    end
    yield
  ensure
    connection.singleton_class.send(:remove_method, :execute)
  end
end
