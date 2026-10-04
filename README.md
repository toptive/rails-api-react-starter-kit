# Rails API + React starter kit

Rails 8.1 JSON API, PostgreSQL and a React/TypeScript SPA in `frontend/`.
Use rvm's installed Ruby 3.4.10, Node 22.12+ and pnpm (version pinned in `package.json`).

```sh
source ~/.rvm/scripts/rvm && rvm use 3.4.10
bin/setup --skip-server
bin/dev                         # API on :3000
pnpm dev                        # SPA on :5173, in another terminal
```

PostgreSQL must be running. Setup installs dependencies and Git hooks, builds translations
and the API contract, and prepares development and test databases. Optional local overrides
are listed in `.env.example`; copy it to `.env` when needed.

`GET /up` probes Rails; `GET /api/v1/health` returns `{ "data": { "status": "ok" }, "meta": {} }`.
Protected endpoints require a live bearer session. Superadmins mint browser access to `/jobs`
through `POST /api/v1/admin/jobs-access`; see [docs/AUTH.md](docs/AUTH.md).

```sh
bin/rails typelizer:generate
pnpm i18n:build
git add frontend/src/api/generated i18n/locales config/locales
bin/check
pnpm build
```

Read [CLAUDE.md](CLAUDE.md) for the rulebook and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
for the application boundaries. Deployment configuration is documented in [docs/DEPLOY.md](docs/DEPLOY.md).
