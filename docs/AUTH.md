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
| GET | `/api/v1/auth/google/start` | Redirect to Google with signed, expiring state |
| GET | `/api/v1/auth/google/callback` | Verify Google identity and hand off a bearer in the URL fragment |
| POST | `/api/v1/auth/sudo` | Reauthenticate with password or magicLinkToken |
| DELETE | `/api/v1/auth/impersonation` | End impersonation and preserve admin session; 204 |
| POST | `/api/v1/admin/jobs-access` | Issue a single-use browser handoff URL; 201 |

All data responses pass through Alba and generate committed Typelizer types and route helpers.
Auth objects contain an organization, a membership and an organizations list; see
[TENANCY.md](TENANCY.md) for organization selection and isolation. Locale
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
must use the link. `require_sudo!` returns `403 sudo_required` when the window is missing or
expired, and for impersonation. Email requests, password changes, account preview and account
deletion all require sudo; email confirmation requires the bearer and the emailed token.

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
`Invitation.open_for_email?`. Registration validates the consent checkbox and stores its timestamp,
IP and version map in `legal_accepted_at`, `legal_accepted_ip_address` and `legal_accepted_versions`.
The map is empty when no published legal versions exist; no versions are inferred from the checkbox.
Each published terms/privacy version also gets a retained `legal_acceptances` record linked
to the immutable version. Audit metadata carries its accepted slugs. Registration and token/audit writes are transactional;
email delivery is queued after they commit. Queued mail arguments encrypt the plain access
token using a dedicated application key and a user-bound purpose.

Magic links last 15 minutes, work once and are bound to the recipient address. First confirmation
invalidates the user's other magic links. Subsequent sign-ins consume only the submitted link.
Reset tokens use 15 minutes and change-email contexts seven days. Only hashes are stored.

Emails render in the recipient's locale using `mail.magic_link.*`
and one branded HTML/text layout. Links point to `SPA_ORIGIN/magic-links/:token`; `PUBLIC_URL`
is the development/test origin fallback. Production requires `SPA_ORIGIN` at boot.
Development uses log delivery without message bodies or tokens.
Production uses SMTP environment settings and refuses email-dependent work before writes
when delivery is unavailable. Mail/job logs hide token arguments and access-link route segments.

Turnstile is enabled by `TURNSTILE_REQUIRED=true`. Registration and magic-link requests verify
Cloudflare siteverify before writing: matching hostname/action, success, a five-second deadline,
no retry. Provider refusals and timeouts fail closed. Only the public site key enters bootstrap.

## Google sign-in

Configure `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` together. Bootstrap advertises
`googleEnabled`; both resources return 404 when credentials are absent. The callback URL is
`API_ORIGIN/api/v1/auth/google/callback`. HMAC-SHA256 signed state expires after ten minutes and carries
only a supported locale, web/native client and validated relative return path. The callback
exchanges the code over HTTPS, requires a verified Google email, and links the Google subject
to an existing account or creates one according to signup policy. It confirms the email.

Web handoffs use `PUBLIC_URL/auth/callback#token=...` with expiry, new-account marker and
validated return path; native handoffs use
`NATIVE_SCHEME://auth/callback`. Tokens remain out of query strings and server access logs.
Provider failures return a stable error code in the fragment. Start allows ten requests per
minute; callback allows twenty. Tests stub only Google's HTTP boundary.

## Rate limits

Rails `rate_limit` keys counters by the resolved IP and endpoint in Solid Cache. Tests use
an in-memory store. Each window is one minute: password sign-in, registration and link consumption
allow ten attempts; magic-link requests and sudo allow five. Refusals use `429 rate_limited`,
`details.retryAfter` and `Retry-After: 60`.

## Browser job dashboard

With a superadmin bearer, POST `/api/v1/admin/jobs-access`, then open the returned API-origin
URL. GET `/admin/jobs/session?ticket=...` consumes the signed 60-second ticket exactly once, sets a
five-minute HttpOnly dashboard cookie and redirects to `/admin/jobs`. Every dashboard request checks
the live session, current role and absence of impersonation. The engine has a separate
CSRF-protected browser session; API bearer routes use no cookie session. CORS remains
credential-free. See [ADMIN.md](ADMIN.md) for the complete handoff and impersonation flows.

## Account settings and devices

`PUT /api/v1/settings/profile` updates name (1–120 characters) and supported locale. It has no
avatar field. `GET` and `PUT /api/v1/settings/email-preferences` expose `optionalEmails`;
changes audit `user.optional_emails_started` or `user.optional_emails_stopped` once. Optional
mailers use `ApplicationMailer#optional_email_headers` for the RFC 8058 HTTPS opt-out URL and
`List-Unsubscribe-Post: List-Unsubscribe=One-Click`. Access and invitation mail have no opt-out
headers. `AccountMail.product_update` is the optional mail example and checks the recipient preference before enqueueing.

`GET /api/v1/settings/sessions` returns every live device of the bearer user, newest first,
without pagination or impersonation sessions. The caller's row has `current: true`. Only the
id, agent, IP, authentication time, creation time and current marker are serialized.
`DELETE /api/v1/settings/sessions/:id` revokes a device, including the current one, and audits
`session.revoked`. Another user's id returns 404. Known revoked bearers return
`401 session_expired`; hashes remain until the daily cleanup.

`PUT /api/v1/settings/email` validates a new address and returns 202 with that address, without
changing the user's email. It refuses unavailable email delivery before token writes and limits
requests to five per minute per user across devices. An unchanged address returns
`409 email_unchanged` with `email: validation.email_unchanged`; other field errors use 422.
A seven-day token is bound to the user and old email. Its encrypted delivery argument is queued
after commit; the branded `mail.email_change.*` mail goes to the new address in the user's
locale, linking to `SPA_ORIGIN/settings/email-confirmations/:token`.

`GET /api/v1/settings/email-confirmations/:token` peeks without consuming. POST to
`/api/v1/settings/email-confirmations` applies it under the user lock, deletes all of that user's
change-email tokens and audits `user.email_changed`. Unknown, expired, spent, foreign or
conflicting tokens return `422 email_change_invalid`. POST is limited to ten attempts per
minute per IP. Confirmation does not require sudo.

`PUT /api/v1/settings/password` requires `password` (12–72 bytes) and
`passwordConfirmation`. Validation reports translated field details, including byte-length
bindings and `validation.password_mismatch`. A successful transaction hashes the password,
revokes every existing live session and child impersonation, deletes all user tokens, and issues
a fresh fourteen-day session with a ten-minute sudo window for the current device and organization.
The response is `AuthSession` with a new token; replace the stored bearer. Old bearers return
`session_expired`. The change audits `user.password_changed`. Account deletion is documented in
[PRIVACY.md](PRIVACY.md).
