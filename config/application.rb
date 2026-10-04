require_relative "boot"

require "rails/all"
require "csv"
require_relative "../lib/client_identity"
require_relative "../lib/operations_browser_session"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module StarterKit
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks client_identity.rb operations_browser_session.rb])

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
    config.exceptions_app = ->(env) { Api::ExceptionsController.action(:show).call(env) }
    config.active_job.queue_adapter = :solid_queue
    config.solid_queue.connects_to = { database: { writing: :queue } }
    config.mission_control.jobs.base_controller_class = "ActionController::Base"
    config.mission_control.jobs.http_basic_auth_enabled = false
    config.mission_control.jobs.adapters = [ :solid_queue ]
    csv_locales = CSV.read(File.expand_path("../i18n/translations.csv", __dir__), headers: true).headers.drop(1)
    config.i18n.available_locales = csv_locales.map(&:to_sym)
    config.i18n.default_locale = csv_locales.first.to_sym
    config.generators { |g| g.orm :active_record, primary_key_type: :uuid }
    config.action_controller.wrap_parameters_by_default = false
  end
end
