require "test_helper"
require_relative "../support/billing_requests"

class BillingNoticesTest < ActionDispatch::IntegrationTest
  include BillingRequests

  test "notice sweep queues one localized renewal per full manager and claims the period once" do
    subscription = stored_subscription(offer_id: "pro_yearly", current_period_end: 20.days.from_now)
    @owner.update!(locale: "es")
    admin, = signed_member(role: "admin")
    signed_member(role: "member")
    signed_member(role: "admin", access: "viewer")
    Flags.with(:billing, false) do
      Flags.with(:billing_renewal_notices, true) do
        with_stripe do
          assert_enqueued_jobs 2, only: RenewalNoticeDeliveryJob do
            2.times { BillingNoticeSweepJob.perform_now }
          end
        end
      end
    end
    assert_equal subscription.current_period_end, subscription.reload.renewal_notice_sent_for
    perform_enqueued_jobs(only: RenewalNoticeDeliveryJob)
    assert_equal [ @owner.email, admin.email ].sort, ActionMailer::Base.deliveries.flat_map(&:to).sort
    owner_mail = ActionMailer::Base.deliveries.find { |mail| mail.to == [ @owner.email ] }
    assert_equal I18n.t("mail.renewal_notice.subject", app: "StarterKit", date: subscription.current_period_end.utc.strftime("%Y-%m-%d"), locale: :es), owner_mail.subject
    assert_includes owner_mail.text_part.body.decoded, "123.45 USD"
    assert_nil owner_mail["List-Unsubscribe"]
    assert_equal 1, AuditEvent.where(action: "billing.renewal_notice_queued", organization_id: @organization.id).count
  end

  test "disabled sweep or ineligible subscriptions do not preview or queue mail" do
    subscription = stored_subscription(offer_id: "pro_yearly", current_period_end: 20.days.from_now)
    Net::HTTP.stub(:new, ->(*) { flunk "Ineligible subscription must not call Stripe" }) do
      Flags.with(:billing_renewal_notices, false) { BillingNoticeSweepJob.perform_now }
      Flags.with(:billing_renewal_notices, true) do
        [ { cancel_at_period_end: true }, { cancel_at_period_end: false, paused: true },
          { paused: false, status: "past_due" }, { status: "active", current_period_end: 30.days.from_now },
          { current_period_end: 20.days.from_now, offer_id: "pro_monthly" } ].each do |attributes|
          subscription.update!(attributes)
          assert_no_enqueued_jobs(only: RenewalNoticeDeliveryJob) { BillingNoticeSweepJob.perform_now }
        end
      end
    end
  end

  test "failed preview leaves the period unclaimed for the next sweep" do
    subscription = stored_subscription(offer_id: "pro_yearly", current_period_end: 20.days.from_now)
    Flags.with(:billing_renewal_notices, true) do
      with_stripe(error: :timeout) { assert_no_enqueued_jobs(only: RenewalNoticeDeliveryJob) { BillingNoticeSweepJob.perform_now } }
    end
    assert_nil subscription.reload.renewal_notice_sent_for
    refute AuditEvent.exists?(action: "billing.renewal_notice_queued", organization_id: @organization.id)
  end

  test "recurring jobs have the declared schedules and only supported queues" do
    config = Rails.application.config_for(:recurring, env: "production")
    assert_equal "0 8 * * * Etc/UTC", config.fetch(:billing_notice_sweep).fetch(:schedule)
    assert_equal "SessionCleanupJob", config.fetch(:purge_expired_sessions).fetch(:class)
    assert_equal "InvitationCleanupJob", config.fetch(:purge_expired_invitations).fetch(:class)
    assert config.values.all? { |job| %w[default marketing].include?(job.fetch(:queue)) }
  end
end
