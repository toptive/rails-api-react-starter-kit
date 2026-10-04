class BillingNoticeSweepJob < ApplicationJob
  queue_as :default

  def perform
    Billing.notice_sweep
  end
end
