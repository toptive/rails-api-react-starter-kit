# Rails API + React starter kit

A Toptive product template: Rails 8.1 JSON API on Ruby 3.4.10 and PostgreSQL, with one
React/TypeScript SPA in `frontend/`. The API supports bearer sessions, tenant-scoped
organizations, invitations, account settings, superadmin tools, translated content,
Stripe billing, private uploads and optional analytics/AI providers. Alba serializers
and Rails routes generate the committed TypeScript contract.

The shared SPA uses TanStack Router and React Query and supports adding Capacitor.
The deployment image builds the SPA into Rails `public/`, serves it through Thruster,
and runs Solid Queue, Cache and Cable on PostgreSQL. Mission Control Jobs lives at
`/admin/jobs`, protected by a live superadmin browser handoff.

## Start locally

Install PostgreSQL, Node 22.12+ and the pnpm version pinned in the root `package.json`.
Use rvm's installed Ruby; do not install another Ruby inside the repository.

```sh
source ~/.rvm/scripts/rvm && rvm use 3.4.10
bin/setup --skip-server
bin/dev                         # API on :3000
# Another terminal, from the repository root:
pnpm dev                        # SPA on :5173
```

Setup installs dependencies and Git hooks, builds translations and the API contract, and
prepares development/test databases. Optional local settings are listed in `.env.example`.
Store credentials with `cred`; never put them in Git. `GET /health` checks PostgreSQL and
returns plain `ok` (503 when unavailable); `/api/v1/health` uses the API envelope.
`/up` is the lightweight Rails process probe.

## Build and verify

```sh
pnpm i18n:build
bin/rails typelizer:generate
git add frontend/src/api/generated i18n/locales config/locales
bin/check
pnpm build
docker build -t starter_kit:local .
```

`bin/check` runs Ruby style, architecture, security audits, Rails tests, generated-contract
checks, frontend typecheck/lint/tests and dependency audits. The Git hooks and Kamal
pre-build hook enforce the gates. Commands run at the repository root; there is one
package manifest and lockfile.

Start a product with [docs/NEW_PRODUCT.md](docs/NEW_PRODUCT.md) and `bin/rename`.
[docs/DEPLOY.md](docs/DEPLOY.md) covers image smoke tests, runtime variables and Kamal;
[docs/NEW_SERVER.md](docs/NEW_SERVER.md) covers shared-server provisioning.
Read [CLAUDE.md](CLAUDE.md) for the rulebook and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for application boundaries. Domain references
for [authentication](docs/AUTH.md), [tenancy](docs/TENANCY.md), [billing](docs/BILLING.md),
[translations](docs/I18N.md) and the [type contract](docs/TYPE_CONTRACT.md) explain the extension points.
