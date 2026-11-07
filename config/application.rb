require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Shared PII scrubbing. Plain Ruby, required here because the logger is built
# before autoloading is available; excluded from autoload_lib below.
require_relative "../lib/pii"

module OfferzenTechinicalAssessment
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks pii pii.rb])

    # Every log line, including error logs, passes through the PII scrubber.
    # production.rb builds its own logger, so it passes this formatter too.
    config.log_formatter = Pii::LogFormatter.new

    # Active Storage's default blob links work without signing in. Exports are
    # served only through ExportsController#show, so draw none of those routes.
    config.active_storage.draw_routes = false

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
