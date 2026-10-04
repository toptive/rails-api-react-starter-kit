class SessionCleanupJob < ApplicationJob
  queue_as :default

  def perform
    Session.purge_expired
  end
end
