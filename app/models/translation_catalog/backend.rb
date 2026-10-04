class TranslationCatalog::Backend < I18n::Backend::Simple
  protected

  def lookup(locale, key, scope = [], options = {})
    flat_key = I18n.normalize_keys(locale, key, scope, options[:separator]).drop(1).join(".")
    value = TranslationCatalog.values(locale)[flat_key]
    return value.gsub(/\{\{(\w+)\}\}/, '%{\1}') if value

    super
  end
end
