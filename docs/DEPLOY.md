# Deployment configuration

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
| `SPA_ORIGIN`, `PUBLIC_URL` | SPA origin for mail links and CORS (default `http://localhost:5173`) |
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
| `CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL`, `CABLE_DATABASE_URL` | Optional dedicated Solid DB connection overrides |
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
session lifetimes, signup behavior and the signed `/jobs` browser access cookie.
