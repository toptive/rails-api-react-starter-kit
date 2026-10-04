class RenewalNotice
  def self.deliver(organization_id, subscription_id, user_id, preview)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    scope = Session::Scope.new(organization: organization)
    subscription = BillingSubscription.for(scope).find_by(id: subscription_id)
    membership = Membership.for(scope).find_by(user_id: user_id, role: %w[owner admin], access: "full")
    return unless subscription && membership

    AccountMail.require_available!
    RenewalNoticeMailer.with(user: membership.user, organization: organization, subscription: subscription, preview: preview).notice.deliver_now
  end
end
