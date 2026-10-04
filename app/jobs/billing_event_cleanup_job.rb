class BillingEventCleanupJob < ApplicationJob
  queue_as :default

  def perform
    Billing.purge_events
  end
end
