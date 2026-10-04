Typelizer.configure do |config|
  config.output_dir = Rails.root.join("frontend/src/api/generated/serializers")
  config.types_import_path = "./index"
  config.verbatim_module_syntax = true
  config.prefer_double_quotes = true
  config.routes.enabled = true
  config.routes.output_dir = Rails.root.join("frontend/src/api/generated/routes")
  config.routes.include = [ %r{\A/api/v1/} ]
end
