ActiveSupport::Notifications.subscribe("translations.changed") { TranslationCatalog.invalidate! }
Rails.application.config.to_prepare { TranslationCatalog.install! }
