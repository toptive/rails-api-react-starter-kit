# Admin API

## Access and contracts

All `/api/v1/admin/` resources require a live superadmin session without impersonation.
Anonymous callers, ordinary users, expired/revoked sessions and impersonating sessions get
404. Each action also authorizes through Pundit. Responses use Alba and committed Typelizer
types; request fields are flat camelCase. Collection metadata is `meta.pagination` with
`page`, `perPage`, `total`, `totalPages`; the default page size is 25 and maximum is 100.

| Resource | Operations |
|---|---|
| `/dashboard` | GET global user and organization counts |
| `/users` | GET, search `q` across name/email; newest first |
| `/users/:id` | GET user and organizations; PUT `role` (`user` or `superadmin`) |
| `/users/:id/impersonation` | POST `reason`, return an `AuthSession` with a new target token |
| `/organizations` | GET, search `q` across names; member counts, newest first |
| `/organizations/:id` | GET organization and memberships with users |
| `/translations` | GET key/value search, `missing=<locale>` and pagination |
| `/translations/:key` | PUT a `locale`/`value` cell; keys are URL encoded |
| `/translation-fills` | POST `locale`; fill missing cells with OpenRouter |
| `/legal-documents` | GET the three documents with versions |
| `/legal-documents/:slug` | GET one document |
| `/legal-documents/:slug/versions` | POST `titles`, `bodies`, optional `note`/`publish` |
| `/legal-documents/:slug/versions/:number/publication` | POST to publish; 201 document |
| `/audit-events` | GET search and pagination; newest first |
| `/jobs-access` | POST; 201 `{ url }` for the browser handoff |

User role changes audit `user.role_changed` with `from` and `to`. Search treats SQL wildcard
characters literally. Organization discovery is global for authorized superadmins; every
membership lookup still enters through `Membership.for` with that discovered organization.
The admin user policy is separate from the account settings policy.

## Impersonation

Reasons contain 5–255 characters. Self and superadmin targets return 403; missing targets
return 404. Starting impersonation creates an `impersonations` row and an eight-hour session
with the parent admin session and user IDs, no sudo and no renewal. The original admin token
stays active. The response includes the target user, impersonator and `canManage`.

The SPA retains its admin token separately, uses the target token, and shows the bootstrap
impersonator banner. Sensitive user operations retain the impersonator ID in audit events.
`DELETE /api/v1/auth/impersonation` revokes the child and ends its impersonation record; the
client then restores the original admin token. Signing out while impersonating also revokes
the parent. Revoking the parent cascades to its children. Sudo and all admin APIs remain
unavailable during impersonation. Audits are `impersonation.started` and `impersonation.stopped`.

## Texts

See [I18N.md](I18N.md) for the three catalogue layers, synchronization, empty-cell semantics,
OpenRouter error responses and invalidation across processes. Runtime edits survive deploys.

## Legal documents and consent

The `terms`, `privacy` and `cookies` documents are created on demand. Versions are numbered
under a document row lock, newest first. Content is immutable: creating a revision adds a new
version. Titles and bodies are locale maps with nonempty English required. Titles have a
255-character cap per locale, bodies 100,000, and optional notes 255. Unsupported locale keys
and non-string values are refused. `publish: true` creates and publishes atomically.
Publication is idempotent for the current version. Actions audit `legal.version_created` and
`legal.published`, with slug and number.

Public `GET /api/v1/legal-pages/:slug` selects the published version in the request locale,
falling back to English independently for title and body. Bodies are plain text: blank lines
separate paragraphs and `## ` marks a heading. Clients must render this safely as text.
Unknown/unpublished documents return 404. ETags are `"<slug>:<number>:<locale>"` with public
revalidation and empty 304 responses. Draft creation leaves the public page unchanged.

Registration validates the consent checkbox and records the exact published terms/privacy
versions in the same transaction as the user. Unpublished documents have no version to accept.
`legal_acceptances` links each published version, retains its version map, email SHA-256 hash,
IP and timestamp, and nullifies its user reference on deletion. Legacy snapshot records remain
readable. The user's acceptance summary records the version numbers; cookies are not required
for registration.

## Audit viewer

Events are append-only at the database boundary. UUID searches match actor or subject IDs;
other searches use escaped ILIKE on action. Actor emails are preloaded for the current page
and become null when an actor is deleted. Metadata keys remain verbatim. The log indexes
actor ID, subject ID and creation time; the API omits client IPs from its response.

## Mission Control

Bootstrap exposes `app.jobsDashboard: true`. POST `/api/v1/admin/jobs-access` returns a URL
on configured `API_ORIGIN` and audits `admin.jobs_dashboard_opened`. It does not set cookies.
The signed ticket has a 60-second expiry and a database row consumed under a lock exactly
once. A browser GET `/jobs/session?ticket=...` checks the ticket and live admin session, sets
a signed five-minute HttpOnly, SameSite=Strict cookie scoped to `/jobs` (Secure in production),
and returns 302 to Mission Control at `/jobs`.

Every dashboard request checks current role, session expiry/revocation and impersonation.
The engine has its own CSRF-protected browser session; JSON API requests retain bearer auth
and credential-free CORS. Open the returned URL in a new tab. Session cleanup removes expired
tickets. See [DEPLOY.md](DEPLOY.md) for `API_ORIGIN` and infrastructure settings.
