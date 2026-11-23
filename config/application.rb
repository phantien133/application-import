require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ImportDemo
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Rails.cache backed by Redis (development and production).
    # REDIS_CACHE_URL wins over REDIS_URL so cache can live on its own instance/db.
    # Cache errors are reported and treated as misses instead of raising.
    config.cache_store = :redis_cache_store, {
      url: ENV.fetch("REDIS_CACHE_URL") { ENV.fetch("REDIS_URL", "redis://localhost:6379/0") },
      namespace: "import_demo:cache",
      connect_timeout: 1,
      read_timeout: 0.5,
      write_timeout: 0.5,
      reconnect_attempts: 1,
      error_handler: ->(method:, returning:, exception:) {
        Rails.error.report(exception, handled: true, severity: :warning, context: { method:, returning: })
      }
    }
  end
end
