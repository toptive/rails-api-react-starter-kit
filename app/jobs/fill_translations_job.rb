class FillTranslationsJob < ApplicationJob
  queue_as :default

  def perform(id)
    TranslationFill.complete!(id)
  end
end
