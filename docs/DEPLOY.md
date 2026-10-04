# Deployment configuration

Production requires `SPA_ORIGIN` and `API_ORIGIN`; boot stops if either is unset or blank. `PUBLIC_URL` supplies the public SPA URL for billing and SEO; it defaults to `SPA_ORIGIN`. `TENANCY=multi` creates personal organizations; `TENANCY=single`
shares the default organization. Unknown modes stop boot. See [TENANCY.md](TENANCY.md).

`Dockerfile` uses Ruby 3.4.10, installs production gems, precompiles Bootsnap and Propshaft
assets for Mission Control, and runs Rails through Thruster as an unprivileged user.
The SPA is built separately with `pnpm build`; `frontend/dist` is its deployable artifact.

`config/deploy.yml` is a Kamal template. Replace its server, hostname, image and registry
username for a product before deployment. `bin/check` must pass before building. The server
entrypoint runs `db:prepare`, including Solid adapter schemas; it never seeds production.
Development/test setup refuses a production environment.

## Environment

| Variable | Purpose |
|---|---|
| `API_ORIGIN` | Public API origin for browser jobs handoffs and one-click unsubscribe (required in production) |
| `OPENROUTER_API_KEY` | Optional OpenRouter credential for admin translation fills |
| `OPENROUTER_MODEL` | Optional translation model (default `openai/gpt-4o-mini`) |
| `SPA_ORIGIN` | SPA origin for mail links and CORS; required in production |
| `PUBLIC_URL` | Public SPA base URL for checkout, portal, sitemap and robots; defaults to `SPA_ORIGIN` |
| `TENANCY` | `multi` (default) or `single`; shared mode creates the default organization at boot/seed |
| `APP_NAME`, `SIGNUP_MODE` | Product name; open/invite/closed signup policy |
| `TRUSTED_PROXY_CIDRS` | Comma-separated proxy networks allowed to supply client forwarding headers |
| `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_AUTHENTICATION` | Production mail server; port defaults to 587 with STARTTLS |
| `SMTP_USERNAME`, `SMTP_PASSWORD` | SMTP credentials supplied through environment/cred |
| `MAIL_FROM`, `MAIL_FROM_NAME` | Email sender; optional locale overrides suffixed `_ES`/`_EN` |
| `TURNSTILE_REQUIRED` | `true` requires bot verification for registrations and magic-link requests |
| `TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY`, `TURNSTILE_HOSTNAME` | Public widget key, siteverify credential and accepted hostname |
| `API_URL` | Vite's dev proxy origin (default `http://localhost:3000`) |
| `PORT`, `VITE_PORT` | API and frontend dev ports |
| `RAILS_MAX_THREADS` | Puma threads and database connection pool |
| `JOB_CONCURRENCY` | Solid Queue worker processes |
| `DB_HOST` | Production PostgreSQL host (default `localhost`) |
| `DATABASE_URL` | Optional primary PostgreSQL connection override |
| `CACHE_DATABASE_URL`, `CABLE_DATABASE_URL` | Optional dedicated Solid DB connection overrides |
| `STARTER_KIT_DATABASE_PASSWORD` | Password for production PostgreSQL role |
| `SECRET_KEY_BASE` | Production Rails signing secret, supplied at runtime |
| `KAMAL_REGISTRY_PASSWORD` | Image registry credential, supplied through Kamal secrets |
| `SOLID_QUEUE_IN_PUMA` | Run the queue supervisor beside Puma in a single-container deployment |
| `RAILS_LOG_LEVEL` | Production log verbosity (default `info`) |

Secrets are environment values, never image layers or committed dotenv files. Use `cred` to
populate an ignored local `.env` or run commands with secrets; the checked-in `.env.example`
and `.kamal/secrets` contain only placeholders/environment references.

Production enables HTTPS/HSTS behind the TLS-terminating proxy. The job dashboard requires
a live superadmin session; no default login credentials are configured. Do not deploy placeholder hosts or registry settings.

Primary database schema loads use `db/structure.sql` to retain the append-only audit trigger.
Production mail uses SMTP; development logs delivery metadata. See [AUTH.md](AUTH.md) for
session lifetimes, signup behavior and the signed `/admin/jobs` browser access cookie.

The Docker server entrypoint runs `db:prepare` followed by `i18n:sync` before listening. Runtime
text edits survive synchronization; see [I18N.md](I18N.md).

## Platform providers

Billing is off by default. Set `BILLING_ENABLED=true`, `BILLING_MODE=test|live`,
the mode's `STRIPE_<MODE>_SECRET_KEY` and `STRIPE_<MODE>_WEBHOOK_SECRET`, and
`STRIPE_<MODE>_PRICE_PRO_MONTHLY` / `STRIPE_<MODE>_PRICE_PRO_YEARLY`.
Production refuses enabled billing with missing configuration or keys from another mode.
`BILLING_TEST_OPERATOR_USER_IDS` is a comma-separated UUID list; superadmins also qualify.
`BILLING_RENEWAL_NOTICES=true` enables the daily renewal sweep independently of sales.
See [BILLING.md](BILLING.md) for offers, webhooks and reconciliation.

Solid Queue inherits the primary Active Record connection. Its tables live in the primary
schema so webhook inbox rows and jobs share a database transaction. Keep that connection
shared; a dedicated queue database would break this guarantee. Cache and Cable retain
their dedicated PostgreSQL databases. Existing queue databases from older checkouts are
unused; drain their pending jobs before migrating a deployed product to this configuration.

Uploads need `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, and optionally
`S3_ENDPOINT` / `S3_REGION`. The bucket must be private. Configure bucket CORS for the
SPA origin, PUT/GET and the content-type header. Analytics uses `POSTHOG_API_KEY` with
`POSTHOG_HOST` (HTTPS); missing key means no delivery.

AI uses `OPENROUTER_API_KEY` / `OPENROUTER_MODEL`, `FAL_KEY`, and
`GOOGLE_API_KEY` / `GEMINI_MODEL`. Sentry uses optional `SENTRY_DSN`,
`SENTRY_ENV` and `KAMAL_VERSION`. See [PLATFORM.md](PLATFORM.md).

The deploy template starts with `SITE_INDEXING=0`; set it to `1` at launch.
`CANONICAL_HOST` (defaults to the public URL host in production) names the public host; the configured API origin remains
usable and `/health` bypasses the redirect. Health probes use `/health`, which checks
PostgreSQL readiness and returns 503 when unavailable. See [SEO.md](SEO.md).
