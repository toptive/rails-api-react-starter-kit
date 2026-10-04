class InvitationDeliveryJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 1.hour, jitter: 0, attempts: 5

  def perform(organization_id, id, encrypted_token, locale)
    Invitation.deliver_notification(organization_id, id, encrypted_token, locale)
  end
end
