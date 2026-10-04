# Platform

## Uploads

POST `/api/v1/direct-uploads` authenticates and authorizes the current membership, then
returns 201 `DirectUpload { url, key, method: "PUT", headers }`. Storage credentials and a
bucket are required; otherwise it returns 503 `uploads_not_configured`. Limit: 60/minute.

| Kind | Types | Maximum bytes |
|---|---|---|
| image | JPEG, PNG, WebP, GIF | 10,000,000 |
| document | PDF, JPEG, PNG | 20,000,000 |
| avatar | JPEG, PNG, WebP | 2,000,000 |

SVG is never allowed. Invalid kinds, MIME types and nonpositive/noninteger sizes return the
contract's named 422 codes. Keys are `uploads/<organizationId>/<uuid>/<safe filename>`.
Presigned PUTs expire after ten minutes and sign the content type and length. The browser
supplies the returned content-type header; its file body supplies the matching length.

Owning models must call `Uploads.verify(scope, key, kind)` before persisting a key. It
checks tenant ownership and safe key structure, HEAD size/type and the first stored bytes.
Missing/oversized/spoofed objects return 422 `upload_incomplete`. Verification is a domain
API; the template's profile has no avatar field. Keep buckets private. For authorized reads,
`Uploads.url(scope, key)` signs a five-minute GET and checks the tenant prefix.

## Analytics and flags

POST `/api/v1/events` is public and accepts 120/minute. Missing/non-string/empty name is
400 `bad_request`. Client names are `page_viewed` (page slug ≤80 bytes) and
`cta_clicked` (cta slug ≤40, page ≤80). Unknown client names, server-only names and unsafe
properties are ignored; accepted responses are 202 `EventReceipt { accepted: true }`.

Every producer calls `Analytics.track`. Its single catalogue declares permitted properties
for account, onboarding, organization, invitation and subscription events. Slugs permit
letters, digits, underscore, dot and dash, excluding emails and URLs. Writes track after
commit. Unknown server event names raise in development/test and drop in production.

Without `POSTHOG_API_KEY`, tracking emits only local notifications. With a key and HTTPS
`POSTHOG_HOST`, a bounded executor schedules delivery outside requests: eight workers,
short timeouts, no retry. Events disable geo-IP enrichment. Anonymous events have a random
distinct ID and disable person profiles; authenticated events carry only the user UUID.
Undeclared properties and tenant IDs are not sent to PostHog.

`Flags.enabled?(name)` reads declared env/config flags; unknown names raise. Billing and
renewal notices default off, Turnstile defaults off, indexing defaults off in production
and on elsewhere. Only public billing appears in bootstrap. Tests can use
`Flags.with(name, boolean) { ... }`; overrides are scoped to the current thread.
Production checks enabled billing/Turnstile readiness before serving; PostHog needs a host
when its key is set. Flags cannot silently enable unconfigured providers.

## Abuse protection and AI

Configured Turnstile verifies registration and magic-link tokens before writes. Siteverify
checks success, hostname and the action `registration` or `magic_link`, with one attempt
and a five-second total timeout. Hostname defaults to the public URL host. Refusals return
422 `turnstile_failed` with translated validation details on `turnstileToken`. Bootstrap
returns the required switch and public site key. Production rejects missing or Cloudflare
test keys.

`Ai.chat(messages)` and `Ai.translate_strings(map, from:, to:)` use OpenRouter.
`Ai.fal(model, input)` uses fal.ai; `Ai.gemini(prompt)` uses Google. Each provider requires
its own configured key, never falls back, and uses bounded HTTP calls without retry.
Missing keys return 503 `ai_not_configured`; transport/DNS/timeouts or invalid replies
return 503 `ai_unavailable`. Translation output must preserve keys and placeholders.
Admin fills run through `FillTranslationsJob`; see [ADMIN.md](ADMIN.md) for 201/202.

## Monitoring, health and jobs

Sentry is inactive without `SENTRY_DSN`. With a DSN, request and job exceptions use the
Rails integration. Only the user UUID is retained: request bodies, headers, cookies, query,
URL, breadcrumbs, contexts, tags, attachments and exception locals are scrubbed.
Messages are scrubbed for user-originated errors; other exception messages are retained
for diagnosis. See [SECURITY.md](SECURITY.md).
`Monitoring.report(exception, user_id: ...)` reports rescued exceptions. Environment comes
from `SENTRY_ENV`, release from `KAMAL_VERSION`; tracing is disabled.

GET `/health` runs SELECT 1 with a two-second deadline. It returns plain `ok` (200) or
`database unavailable` (503), always `Cache-Control: no-store`, without authentication,
rate limits, locale catalogue access or canonical redirect.

Solid Queue consumes only default and marketing. Primary tables share the application's
connection for atomic enqueue; Cache and Cable use their own PostgreSQL databases.
`config/recurring.yml` declares session/token/impersonation/ticket cleanup at 03:00 UTC,
invitation purge at 03:15 UTC, renewal sweep at 08:00 UTC and finished-job cleanup hourly.
Jobs delegate one model call. Mission Control lives at `/admin/jobs` behind a short-lived
cookie and live superadmin session; access details are in [ADMIN.md](ADMIN.md).

See [DEPLOY.md](DEPLOY.md) for provider environment variables, [BILLING.md](BILLING.md) for
payments and [SEO.md](SEO.md) for indexing.
