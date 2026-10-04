class ProcessStripeEventJob < ApplicationJob
  queue_as :default
  self.enqueue_after_transaction_commit = false
  retry_on ApiError, wait: :polynomially_longer, attempts: 10

  def perform(id)
    Billing.process_event(id)
  end
end
