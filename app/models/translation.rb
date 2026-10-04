class Translation < ApplicationRecord
  validates :key, presence: true
  validates :locale, inclusion: { in: ->(_) { TranslationCatalog.locales } }
  validates :value, length: { maximum: 20_000 }, allow_blank: true
  after_commit :reload_catalogue

  def self.entries(query: nil, missing: nil)
    if missing.present? && !TranslationCatalog.locales.include?(missing)
      raise ApiError.unprocessable(:validation_failed, User.validation_details(:missing, "validation.inclusion"))
    end
    by_key = all.group_by(&:key)
    keys = (TranslationCatalog.reference_rows.keys | by_key.keys).sort
    keys.filter_map do |key|
      entry = entry_for(key, by_key.fetch(key, []))
      next if query.present? && ![ key, *entry[:values].map { |cell| cell[:value] } ].any? { |text| text.downcase.include?(query.downcase) }
      next if missing.present? && entry[:values].find { |cell| cell[:locale] == missing }[:value].present?

      entry
    end
  end

  def self.entry_for(key, rows)
    { key: key, values: TranslationCatalog.locales.map do |locale|
      row = rows.find { |cell| cell.locale == locale }
      { locale: locale, value: row&.value || TranslationCatalog.reference_rows.dig(key, locale).to_s, edited: row&.edited || false }
    end }
  end
  private_class_method :entry_for

  def self.edit!(key, attributes, scope, request)
    User::Input.validate!(attributes, string_fields: %i[locale value], required: %i[locale value])
    transaction do
      # Serialize sync, edits and fill persistence; provider calls stay outside this lock.
      lock_catalogue!
      row = find_or_initialize_by(key: key, locale: attributes[:locale])
      row.update!(value: attributes[:value], edited: true)
      Audit.record("translation.updated", scope: scope, subject: row, metadata: { key: key, locale: row.locale }, request: request)
    end
    entry_for(key, where(key: key).to_a)
  end

  def self.fill!(attributes, scope, request)
    User::Input.validate!(attributes, string_fields: [ :locale ], required: [ :locale ])
    locale = attributes[:locale]
    unless TranslationCatalog.locales.drop(1).include?(locale)
      raise ApiError.unprocessable(:validation_failed, User.validation_details(:locale, "validation.inclusion"))
    end
    Ai.require_configured!
    keys = entries(missing: locale).map { |entry| entry[:key] }
    source = TranslationCatalog.values(TranslationCatalog.locales.first)
    translated = keys.each_slice(40).each_with_object({}) do |batch, result|
      pairs = batch.to_h { |key| [ key, source[key].presence || key ] }
      result.merge!(Ai.translate_strings(pairs, from: TranslationCatalog.locales.first, to: locale))
    end
    count = transaction do
      lock_catalogue!
      missing = entries(missing: locale).map { |entry| entry[:key] }
      rows = translated.filter_map do |key, value|
        next unless missing.include?(key)

        row = find_or_initialize_by(key: key, locale: locale)
        row.update!(value: value, edited: true)
        Audit.record("translation.updated", scope: scope, subject: row, metadata: { key: key, locale: locale }, request: request)
        row
      end
      Audit.record("translation.filled", scope: scope, metadata: { locale: locale, count: rows.size }, request: request)
      rows.size
    end
    { count: count }
  end

  def self.sync!
    result = transaction do
      lock_catalogue!
      reference = TranslationCatalog.reference_rows
      existing = all.index_by { |row| [ row.key, row.locale ] }
      inserts = []
      updates = 0
      reference.each do |key, values|
        values.each do |locale, value|
          row = existing[[ key, locale ]]
          if row.nil?
            inserts << { key: key, locale: locale, value: value, edited: false }
          elsif !row.edited && value.present? && row.value != value
            where(id: row.id).update_all(value: value, updated_at: Time.current)
            updates += 1
          end
        end
      end
      insert_all!(inserts) if inserts.any?
      deleted = where(edited: false).where.not(key: reference.keys).delete_all
      { inserted: inserts.size, updated: updates, deleted: deleted }
    end
    TranslationCatalog.broadcast!
    result
  end

  def self.lock_catalogue!
    connection.execute("SELECT pg_advisory_xact_lock(7240519)")
  end
  private_class_method :lock_catalogue!

  private

  def reload_catalogue = TranslationCatalog.broadcast!
end
