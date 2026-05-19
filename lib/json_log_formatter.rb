require "json"

class JsonLogFormatter < ::Logger::Formatter
  def call(severity, time, progname, msg)
    payload = {
      timestamp: time.iso8601(3),
      level: severity,
      message: format_message(msg),
      service: ENV.fetch("APP_NAME", "myapp"),
      env: Rails.env,
      git_sha: ENV.fetch("GIT_SHA", "unknown")
    }
    payload[:progname] = progname if progname
    JSON.generate(payload) + "\n"
  end

  private

  def format_message(msg)
    case msg
    when Hash then msg
    when Exception then "#{msg.class}: #{msg.message}\n#{msg.backtrace&.join("\n")}"
    else msg.to_s
    end
  end
end
