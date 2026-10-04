class Billing::Webhook
  HANDLED = %w[checkout.session.completed customer.subscription.created customer.subscription.updated
    customer.subscription.deleted customer.subscription.paused customer.subscription.resumed invoice.paid invoice.payment_failed].freeze
  UUID = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i

  def receive(raw, signature)
    secret = Billing.webhook_secret
    raise ApiError.not_found unless secret&.start_with?("whsec_")

    verify!(raw, signature, secret)
    event = JSON.parse(raw)
    valid = event.is_a?(Hash) && event["id"].is_a?(String) && event["id"].match?(/\Aevt_[a-zA-Z0-9_-]+\z/) &&
      event["type"].is_a?(String) && event["livemode"] == Billing.livemode?
    raise ApiError.bad_request(:invalid_signature) unless valid

    enqueue(event) if HANDLED.include?(event["type"])
    { received: true }
  rescue JSON::ParserError, TypeError
    raise ApiError.bad_request(:invalid_signature)
  end

  private

  def verify!(raw, signature, secret)
    raise ApiError.bad_request(:invalid_signature) unless signature.is_a?(String) && signature.bytesize <= 4096

    parts = signature.split(",").map { |part| part.strip.split("=", 2) }
    timestamp = parts.find { |key, _| key == "t" }&.last
    raise ApiError.bad_request(:invalid_signature) unless timestamp&.match?(/\A\d+\z/) && (Time.current.to_i - timestamp.to_i).abs <= 300

    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{raw}")
    matches = parts.any? do |key, value|
      key == "v1" && value&.match?(/\A[0-9a-f]{64}\z/) && ActiveSupport::SecurityUtils.secure_compare(value, expected)
    end
    raise ApiError.bad_request(:invalid_signature) unless matches
  end

  def enqueue(event)
    object = event.dig("data", "object")
    raise ApiError.bad_request(:invalid_signature) unless object.is_a?(Hash)

    subscription, organization = reference(event["type"], object)
    BillingEvent.transaction do
      row = BillingEvent.create!(livemode: event["livemode"], stripe_event_id: event["id"], type: event["type"],
        stripe_subscription_id: subscription, organization_id: organization)
      job = ProcessStripeEventJob.perform_later(row.id)
      raise ApiError.unavailable(:stripe_unavailable) unless job
    end
  rescue ActiveRecord::RecordNotUnique
    # A unique inbox row owns exactly one reconciliation job.
    nil
  end

  def reference(type, object)
    if type == "checkout.session.completed"
      subscription = object["subscription"]
      organization = object.dig("metadata", "organization_id") || object["client_reference_id"]
    elsif type.start_with?("customer.subscription.")
      subscription = object["id"]
      organization = object.dig("metadata", "organization_id")
    else
      details = object.dig("parent", "subscription_details") || {}
      subscription = details["subscription"] || object["subscription"]
      organization = details.dig("metadata", "organization_id")
    end
    subscription = subscription["id"] if subscription.is_a?(Hash)
    subscription = nil unless subscription.is_a?(String) && subscription.match?(/\Asub_[a-zA-Z0-9_-]+\z/)
    organization = nil unless organization.is_a?(String) && organization.match?(UUID)
    [ subscription, organization ]
  end
end
