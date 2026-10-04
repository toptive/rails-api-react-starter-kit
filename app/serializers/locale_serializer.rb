class LocaleSerializer
  include ApplicationSerializer

  def serializable_hash = object
end
