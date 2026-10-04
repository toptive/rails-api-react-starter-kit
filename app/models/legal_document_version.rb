class LegalDocumentVersion < ApplicationRecord
  belongs_to :legal_document, inverse_of: :versions
  belongs_to :created_by, class_name: "User", optional: true
  validates :number, numericality: { only_integer: true, greater_than: 0 }
  validates :note, length: { maximum: 255 }
  validate :locale_text
  validate :immutable_text, on: :update

  def localized(field, locale)
    values = public_send(field)
    values[locale].presence || values.fetch("en")
  end

  private

  def locale_text
    { titles: 255, bodies: 100_000 }.each do |field, maximum|
      values = public_send(field)
      unless values.is_a?(Hash) && values["en"].is_a?(String) && values["en"].present?
        errors.add(field, "validation.english_required")
      end
      unless values.is_a?(Hash) && values.all? { |locale, value| TranslationCatalog.locales.include?(locale) && value.is_a?(String) }
        errors.add(field, "validation.cast")
        next
      end
      errors.add(field, :too_long, count: maximum) if values.values.any? { |value| value.length > maximum }
    end
  end

  def immutable_text
    %w[legal_document_id number titles bodies note created_by_id].each do |field|
      errors.add(field, "validation.invalid") if will_save_change_to_attribute?(field)
    end
  end
end
