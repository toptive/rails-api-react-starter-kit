class TranslationCatalog
  def self.version
    Digest::SHA256.hexdigest(I18n.available_locales.map { |locale| File.read(path(locale)) }.join)
  end

  def self.for_locale(locale)
    raise ApiError.not_found unless I18n.available_locales.map(&:to_s).include?(locale)

    { catalogue: JSON.parse(File.read(path(locale))), locale: locale, version: version,
      etag: %Q("#{locale}:#{version}") }
  end

  def self.path(locale) = Rails.root.join("i18n/locales/#{locale}.json")
  private_class_method :path
end
