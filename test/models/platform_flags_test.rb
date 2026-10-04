require "test_helper"

class PlatformFlagsTest < ActiveSupport::TestCase
  setup do
    @platform_env = ENV.to_h.select { |key, _| key.start_with?("BILLING_", "STRIPE_", "TURNSTILE_", "POSTHOG_") }
    ENV.keys.grep(/\A(?:BILLING_|STRIPE_|TURNSTILE_|POSTHOG_)/).each { |key| ENV.delete(key) }
  end
  teardown do
    ENV.keys.grep(/\A(?:BILLING_|STRIPE_|TURNSTILE_|POSTHOG_)/).each { |key| ENV.delete(key) }
    @platform_env.each { |key, value| ENV[key] = value }
  end

  test "flags default to billing off and readiness collects every missing billing requirement" do
    refute Flags.enabled?(:billing)
    assert_nil Flags.check!
    Flags.with(:billing, true) do
      error = assert_raises(ArgumentError) { Flags.check! }
      assert_includes error.message, "Stripe key"
      assert_includes error.message, "webhook secret"
      assert_includes error.message, "pro_monthly"
      assert_includes error.message, "pro_yearly"
    end
  end

  test "only this mode's keys and all offer prices satisfy the billing boot check" do
    ENV["BILLING_MODE"] = "live"
    ENV["STRIPE_TEST_SECRET_KEY"] = "sk_test_stub"
    ENV["STRIPE_TEST_WEBHOOK_SECRET"] = "whsec_stub"
    Flags.with(:billing, true) do
      assert_raises(ArgumentError) { Flags.check! }
      ENV["STRIPE_LIVE_SECRET_KEY"] = "sk_live_stub"
      ENV["STRIPE_LIVE_WEBHOOK_SECRET"] = "whsec_stub"
      ENV["STRIPE_LIVE_PRICE_PRO_MONTHLY"] = "price_live_monthly"
      ENV["STRIPE_LIVE_PRICE_PRO_YEARLY"] = "price_live_yearly"
      assert_nil Flags.check!
    end
  end

  test "Turnstile boot refuses missing or Cloudflare test keys and PostHog needs a host" do
    Flags.with(:turnstile, true) do
      assert_raises(ArgumentError) { Flags.check! }
      ENV["TURNSTILE_SITE_KEY"] = "1x00000000000000000000AA"
      ENV["TURNSTILE_SECRET_KEY"] = "1x0000000000000000000000000000000AA"
      assert_raises(ArgumentError) { Flags.check! }
      ENV["TURNSTILE_SITE_KEY"] = "configured-site"
      ENV["TURNSTILE_SECRET_KEY"] = "configured-secret"
      ENV["TURNSTILE_HOSTNAME"] = "public.example"
      assert_nil Flags.check!
    end
    ENV["POSTHOG_API_KEY"] = "stub"
    assert_raises(ArgumentError) { Flags.check! }
    ENV["POSTHOG_HOST"] = "https://analytics.example"
    assert_nil Flags.check!
  end
end
