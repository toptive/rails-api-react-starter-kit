class InvitationCleanupJob < ApplicationJob
  queue_as :default

  def perform
    Invitation.purge_expired
  end
end
