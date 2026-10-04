# Billing

## Offers and access

Billing uses Stripe Checkout and the customer portal. Offers and plan limits live in
`config/billing.yml`: free has three members, pro is unlimited; monthly pro is 1900 cents
and yearly pro 19000 cents in USD. The offer revision hashes the configured terms.
The client sends only `offerId`, `offerRevision` and `accepted`, never prices.

`BILLING_ENABLED` defaults to false. GET `/api/v1/settings/billing` returns 404 while
disabled unless the current organization has a subscription in the deployment's mode.
Members can read; owners/admins with full access can manage. Overview is
`BillingOverview { plan, subscription, offers, offerRevision, sales, canManage }`.
Sales is `open` for configured live mode, `test` for test operators and `closed` otherwise.
Test operators are non-impersonating superadmins or configured user IDs.

The tenant table is `billing_subscriptions`; every lookup uses
`BillingSubscription.for(scope)`. UUIDs supplied by the browser do not change the tenant.
The placeholder `subscriptions` table is migrated in place. Legacy placeholder records
keep deletion blockers and need Stripe reconciliation before payment management.

A subscription is paid while active, trialing or past_due, unpaused, with a future period
end. The current mode selects entitlements. Account deletion checks open subscriptions in
both modes; canceled/incomplete_expired history still retains the organization.
Unknown Stripe prices yield the free plan, even if checkout metadata names a paid offer.

## Checkout and portal

POST `/api/v1/settings/billing/checkout-session` requires a manager. Guards run in order:
billing enabled, this mode's key, test operator, no paid subscription, known offer/current
revision, agreement accepted, price configured, and a matching Stripe price (active, mode,
amount, currency, recurring interval and interval count). Named refusals match the contract.
Successful creation returns 201 `RedirectUrl { url }`.

The request includes organization metadata on the session and subscription, promotion codes,
fixed adaptive pricing, and the price note in the customer's saved language. The idempotency
key includes organization, user, offer, revision, locale and UTC hour. Stripe request bodies
contain no tax parameters. Success and cancel URLs are on `PUBLIC_URL/settings/billing`
with `?checkout=done` on success. Hosted redirect URLs must use the expected Stripe HTTPS
host. The HTTP adapter pins Stripe API version `2025-09-30.clover`, uses bounded timeouts,
and does not retry. Provider messages are neither exposed nor logged.

POST `/api/v1/settings/billing/portal-session` returns 201 `RedirectUrl` for the existing
customer, including with billing disabled. A missing subscription returns 409
`no_subscription`; unavailable Stripe configuration returns 503 `stripe_unavailable`.
Checkout audits `billing.checkout_started` and tracks `checkout_started` after commit;
portal audits `billing.portal_opened`.

`Billing.limit(scope, key)` returns a configured integer or nil for unlimited; billing
disabled makes all limits unlimited. Missing limit keys raise. Owning models can use
`Billing.with_capacity(scope, key, count: -> { ... }) { ... }` to count and write under the
organization lock.

## Webhooks

POST `/webhooks/stripe/events` reads the original body bytes. It verifies HMAC-SHA256 in
constant time, a 300-second tolerance in both directions, and deployment livemode. Invalid
signatures, malformed events and wrong modes return 400 `invalid_signature`; a missing
mode-specific secret returns 404. It accepts 600 requests/minute independently of sales.
Success is the Stripe acknowledgment `{ received: true }`, outside the API data envelope.

Handled events are checkout completion, subscription create/update/delete/pause/resume,
invoice paid and invoice payment_failed. Other signed events are acknowledged without
storage. The global `billing_events` inbox stores identifiers only, with a unique index on
`livemode, stripe_event_id`. Its nullable organization ID is an untrusted reconciliation
hint, never authorization. Duplicate deliveries are 200 no-ops.

Inbox insertion and `ProcessStripeEventJob` enqueue share the primary connection and
transaction. Do not configure a separate Solid Queue connection. The job fetches current
Stripe subscription truth, locks the event and organization, scopes the tenant lookup and
upserts the subscription. Replayed processing is harmless; old unpaid subscriptions cannot
replace another paid subscription. Outcomes are `synced`, `kept_paid_subscription`,
`unknown_organization`, `no_subscription` and `wrong_mode`. Provider failure retries up
to ten times. Plan/status changes audit `billing.subscription_changed`; paid transitions
track anonymous `subscription_started` / `subscription_canceled` after commit.

## Renewal notices

The default-queue sweep runs daily at 08:00 UTC. `BILLING_RENEWAL_NOTICES=true` enables it
independently of sales. Eligible subscriptions are active/trialing, not canceling or paused,
with a configured yearly offer renewing in 15–25 days. Stripe invoice preview supplies the
discounted amount. Full owners/admins receive a transactional email in their own locale.

The period claim, queued delivery jobs and `billing.renewal_notice_queued` audit are atomic.
Concurrent/repeated sweeps claim a period once. Preview failures leave it eligible for a
later sweep. Delivery checks current membership and retries unavailable mail up to five
times. Billing notices never carry unsubscribe headers.

Provider setup and environment names are in [DEPLOY.md](DEPLOY.md). Request tests use a
fake HTTP transport; no Stripe account or live calls are needed to run the suite.
