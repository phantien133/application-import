require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Disable with ASSUME_SSL=false / FORCE_SSL=false only when TLS is not terminated upstream (e.g. local smoke test).
  config.assume_ssl = ENV.fetch("ASSUME_SSL", "true") == "true"

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = ENV.fetch("FORCE_SSL", "true") == "true"

  # Skip http-to-https redirect for the health check endpoints.
  health_check_paths = %w[ /up /health ].freeze
  config.ssl_options = { redirect: { exclude: ->(request) { health_check_paths.include?(request.path) } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger = ActiveSupport::TaggedLogging.logger($stdout)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Rails.cache uses Redis (see config/application.rb). Fail at boot instead of silently
  # missing every cache read against localhost. SECRET_KEY_BASE_DUMMY marks build-time boots.
  if ENV["REDIS_CACHE_URL"].blank? && ENV["REDIS_URL"].blank? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
    raise "Set REDIS_CACHE_URL or REDIS_URL for Rails.cache in production"
  end

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Allowed hosts, comma-separated (e.g. "api.example.com,.example.com"); see config/deploy.yml.
  app_hosts = ENV.fetch("APP_HOSTS", "").split(",").map(&:strip).reject(&:empty?)

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: app_hosts.first&.delete_prefix("."), protocol: "https" }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # A leading dot allows subdomains (".example.com"). Unset APP_HOSTS disables the check.
  if app_hosts.any?
    config.hosts = app_hosts
    # Skip DNS rebinding protection for the health check endpoints (load balancers use IPs).
    config.host_authorization = { exclude: ->(request) { health_check_paths.include?(request.path) } }
  end
end
