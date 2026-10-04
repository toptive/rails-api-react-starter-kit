Rails.application.config.after_initialize do
  Organization.ensure_default! if Organization.tenancy == "single" && Organization.table_exists?
end
