Rails.application.config.after_initialize do
  Flags.check! if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
end
