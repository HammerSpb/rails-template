require "active_support/core_ext/integer/time"

# Staging mirrors production with a few developer-friendly tweaks:
# verbose deprecations and request locality enabled.

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = true
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }
  config.active_storage.service = :local

  require Rails.root.join("lib/json_log_formatter")
  config.log_tags = [ :request_id ]
  logger = ActiveSupport::Logger.new(STDOUT)
  logger.formatter = JsonLogFormatter.new
  config.logger = ActiveSupport::TaggedLogging.new(logger)

  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "debug")
  config.silence_healthcheck_path = "/up"
  config.active_support.report_deprecations = true

  config.cache_store = :solid_cache_store

  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  config.action_mailer.perform_caching = false
  config.i18n.fallbacks = true

  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [ :id ]

  config.hosts << "myapp-staging.local"
  config.hosts << /.+\.myapp-staging\.local/
end
