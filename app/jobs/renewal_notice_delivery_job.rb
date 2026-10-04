class RenewalNoticeDeliveryJob < ApplicationJob
  queue_as :default
  self.enqueue_after_transaction_commit = false
  retry_on ApiError, wait: 1.hour, attempts: 5

  def perform(organization_id, subscription_id, user_id, preview)
    RenewalNotice.deliver(organization_id, subscription_id, user_id, preview)
  end
end
