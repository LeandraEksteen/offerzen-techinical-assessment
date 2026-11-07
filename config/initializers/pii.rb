# Models declare their PII attributes (pii_attributes) when they load. Load
# them on every code reload so every declaration has run before the first
# request in development. In production, eager loading already does this.
Rails.application.config.to_prepare do
  Rails.autoloaders.main.eager_load_dir(Rails.root.join("app/models"))
end
