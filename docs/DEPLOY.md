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
| `PUBLIC_URL` | Exact allowed SPA origin (default `http://localhost:5173`) |
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
and `.kamal/secrets` contain only placeholders/environment references. A future product can
add provider variables when their domains exist; no provider is contacted by this skeleton.

Production enables HTTPS/HSTS behind the TLS-terminating proxy. The job dashboard remains
closed until a real superadmin session lookup is implemented; no default login credentials
are configured. Do not deploy placeholder hosts or registry settings.
