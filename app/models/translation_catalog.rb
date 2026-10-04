class TranslationCatalog
  TOPIC = "runtime_i18n"
  EVENT = "translations.changed"
  MUTEX = Mutex.new

  def self.locales = Reference.locales
  def self.reference_rows = Reference.rows
  def self.version = snapshot.fetch(:version)
  def self.values(locale) = snapshot.fetch(:catalogues).fetch(locale.to_s, {})

  def self.for_locale(locale)
    raise ApiError.not_found unless locales.include?(locale)

    current = snapshot
    { catalogue: current.fetch(:catalogues).fetch(locale), locale: locale, version: current.fetch(:version),
      etag: %Q("#{locale}:#{current.fetch(:version)}") }
  end

  def self.install!
    I18n.backend = Backend.new unless I18n.backend.is_a?(Backend)
    invalidate!
  end

  def self.listen!
    adapter = ActionCable.server.pubsub
    return if @subscriber && @adapter.equal?(adapter) && @subscriber_pid == Process.pid

    @subscriber = ->(_message) { ActiveSupport::Notifications.instrument(EVENT) }
    @adapter = adapter
    @subscriber_pid = Process.pid
    adapter.subscribe(TOPIC, @subscriber)
  end

  def self.stop!
    ActionCable.server.restart
    @subscriber = nil
    invalidate!
  end

  def self.invalidate!
    MUTEX.synchronize { @snapshot = nil }
  end

  def self.broadcast!
    ActiveSupport::Notifications.instrument(EVENT)
    ActionCable.server.broadcast(TOPIC, { changed: true })
  end

  def self.snapshot
    MUTEX.synchronize do
      @snapshot ||= begin
        maps = locales.to_h do |locale|
          [ locale, reference_rows.sort.to_h do |key, values|
            [ key, values[locale].presence || values[locales.first].to_s ]
          end ]
        end
        if ENV["SECRET_KEY_BASE_DUMMY"].blank? && Translation.table_exists?
          listen!
          rows = Translation.uncached { Translation.order(:key, :locale).pluck(:key, :locale, :value, :edited) }
          rows.each do |key, locale, value, edited|
            next unless locales.include?(locale)
            next if !edited && value.empty?

            maps[locale][key] = value
          end
        end
        maps.transform_values! { |catalogue| catalogue.sort.to_h.transform_values(&:freeze).freeze }
        { catalogues: maps.freeze, version: Digest::SHA256.hexdigest(JSON.generate(maps)) }.freeze
      end
    end
  end
  private_class_method :snapshot
end
