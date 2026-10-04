# Accounts and authentication

The API uses `Authorization: Bearer <token>`. Tokens contain 32 random bytes encoded as
43 base64url characters. `Session.create_for(user, request)` returns the session and its plain
token once. The database stores only SHA-256 hashes. `Session.find_by_token` returns live
sessions; protected endpoints distinguish unknown tokens (`unauthorized`) from known expired
or revoked ones (`session_expired`). Passwords use bcrypt and require 12–72 bytes; password
sign-in requires a confirmed email. Missing accounts and passwordless accounts perform a dummy
bcrypt comparison and return the same invalid-credentials response.

## HTTP resources

| Method | Resource | Behavior |
|---|---|---|
| GET | `/api/v1/bootstrap` | Anonymous or signed-in app configuration and identity |
| GET | `/api/v1/locales/:locale` | Flat translation dictionary, ETag and conditional 304 |
| POST | `/api/v1/auth/registrations` | Name, email, locale and terms consent; 202 with email/newAccount |
| POST | `/api/v1/auth/magic-links` | Always 202 for known and unknown addresses |
| GET | `/api/v1/auth/magic-links/:token` | Peek without consuming; safe for link scanners |
| POST | `/api/v1/auth/magic-links/:token/session` | Consume, confirm and issue a bearer; 201 |
| POST | `/api/v1/auth/sessions` | Email/password sign-in; 201 |
| DELETE | `/api/v1/auth/session` | Revoke current session; 204 |
| POST | `/api/v1/auth/sudo` | Reauthenticate with password or magicLinkToken |
| DELETE | `/api/v1/auth/impersonation` | End impersonation and preserve admin session; 204 |
| POST | `/api/v1/admin/jobs-access` | Mint a dashboard-only signed cookie; 204 |

All data responses pass through Alba and generate committed Typelizer types and route helpers.
Auth objects contain nullable organization/membership fields and an organizations list. Locale
selection prefers the query, then supported Accept-Language tags, the user's locale and English.
Locale dictionaries preserve dotted keys. ETags include the locale and catalogue digest;
responses use `public, no-cache`. Other API responses use `private, no-store`.

## Sessions, sudo and impersonation

Sessions expire after 14 days. A request extends expiry by 14 days when fewer than seven remain,
at most once daily. Last usage is stamped at most once per minute. Device data records the
resolved IP and a user agent capped at 255 characters. `TRUSTED_PROXY_CIDRS` controls which
peers may supply forwarding headers; untrusted peers cannot choose their own rate-limit key.
Cloudflare-specific headers are not used as an independent identity source.

Sign-in starts a ten-minute sudo window. A sign-in for the same user with a valid existing bearer
refreshes that session and returns `token: null`. The client keeps its token. Sudo accepts the
user's password or consumes a magic link belonging to the same user. A passwordless account
must use the link. `require_sudo!` returns `403 sudo_required` for an expired window.

Impersonation sessions never acquire sudo or superadmin authority and never slide their expiry.
Ending impersonation revokes its token and sets the record's ended timestamp. Signing out while
impersonating also revokes the originating admin session. Revoking an admin session revokes
its child impersonation sessions. Sensitive writes record audit events, including registration,
sudo authentication, revocation and impersonation termination. `audit_events` rejects SQL
updates/deletes through a database trigger; `db/structure.sql` preserves that trigger on schema
loads. Solid adapter databases use their own Ruby schema files.

The daily `SessionCleanupJob` purges sessions whose revocation or expiry is older than 30 days
and expired emailed tokens. It runs on the default queue.

## Registration and email

`SIGNUP_MODE` accepts open, invite or closed; an unknown value stops boot. Invite mode consults
`Invitation.open_for_email?`. Registration validates the consent checkbox and invokes the
`User#accept_published_legal!` integration point for published terms/privacy versions. Audit
metadata carries the accepted slugs. Registration and token/audit writes are transactional;
email delivery is queued after they commit. Queued mail arguments encrypt the plain access
token using a dedicated application key and a user-bound purpose.

Magic links last 15 minutes, work once and are bound to the recipient address. First confirmation
invalidates the user's other magic links. Subsequent sign-ins consume only the submitted link.
Reset tokens use 15 minutes and change-email contexts seven days. Only hashes are stored.

Emails render in the recipient's locale using `mail.magic_link.*` or `mail.confirmation.*`
and one branded HTML/text layout. Links point to `SPA_ORIGIN/magic-links/:token`; `PUBLIC_URL`
is the origin fallback. Development uses log delivery without message bodies or tokens.
Production uses SMTP environment settings and refuses email-dependent work before writes
when delivery is unavailable. Mail/job logs hide token arguments and access-link route segments.

Turnstile is enabled by `TURNSTILE_REQUIRED=true`. Registration and magic-link requests verify
Cloudflare siteverify before writing: matching hostname/action, success, a five-second deadline,
no retry. Provider refusals and timeouts fail closed. Only the public site key enters bootstrap.

## Rate limits

Rails `rate_limit` keys counters by the resolved IP and endpoint in Solid Cache. Tests use
an in-memory store. Each window is one minute: password sign-in, registration and link consumption
allow ten attempts; magic-link requests and sudo allow five. Refusals use `429 rate_limited`,
`details.retryAfter` and `Retry-After: 60`.

## Browser job dashboard

With a superadmin bearer, POST `/api/v1/admin/jobs-access` on the API origin, then navigate
the browser to `/jobs` on that same origin. This endpoint sets a signed HttpOnly, SameSite=Strict
cookie scoped to `/jobs`, valid for five minutes and Secure in production. It identifies a
session, not a role claim: every dashboard request checks current session expiry/revocation,
user role and absence of impersonation. Tampering, demotion or sign-out removes access immediately.
The dashboard has its own CSRF-protected browser session middleware; API bearer routes use no
cookie session. CORS remains credential-free. This dashboard access endpoint is the deliberate
cookie exception for the HTML operations engine.
