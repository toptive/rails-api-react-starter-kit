require "csv"

class TranslationCatalog::Reference
  def self.locales = data.fetch(:locales)
  def self.rows = data.fetch(:rows)

  def self.data
    @data ||= begin
      csv = CSV.read(Rails.root.join("i18n/translations.csv"), headers: true)
      locales = csv.headers.drop(1)
      { locales: locales.freeze, rows: csv.to_h { |row| [ row["key"], locales.to_h { |locale| [ locale, row[locale].to_s ] } ] }.freeze }.freeze
    end
  end
  private_class_method :data
end
