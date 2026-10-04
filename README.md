# Rails API + React starter kit

Rails 8.1 on Ruby 3.4.10, PostgreSQL and one shared React 19 SPA with TanStack Router,
React Query, Tailwind and owned shadcn components. Alba + Typelizer generate the API types
and route helpers used by the SPA. Opaque bearer sessions support magic links, passwords,
Google sign-in, sudo and impersonation. Tenant policies, billing, runtime translations,
legal publishing and an administrator jobs dashboard are included.

```sh
source ~/.rvm/scripts/rvm && rvm use 3.4.10
bin/setup --skip-server
bin/dev
# In a second terminal:
pnpm dev
```

Run frontend commands from the root: `pnpm dev`, `pnpm build`, `pnpm typecheck`, `pnpm lint`,
`pnpm test` and `pnpm i18n:build`. The API runs on 3000, Vite on 5173. Product text comes
from `i18n/translations.csv`; forms use react-hook-form and Zod. Theme tokens live in
`frontend/src/styles/theme.css`.

`bin/check` runs backend architecture, style, security and request tests, generated contract
and locale checks, frontend gates, and 31 real browser journeys through `bin/e2e`. The browser
runner owns disposable databases and processes, including a local Stripe HTTP stub. There is
no CI; pre-commit checks staged changes and pre-push runs the full gate.

`pnpm build` writes the SPA and prerendered public pages into `public/`. Docker builds both
frontend and Rails, and serves them through Thruster. The container prepares databases and
synchronizes runtime text before listening. Kamal uses shared PostgreSQL.

Read [CLAUDE.md](CLAUDE.md) for the rulebook, [GATES.md](docs/GATES.md) for checks,
[TYPE_CONTRACT.md](docs/TYPE_CONTRACT.md) for generation, [DESIGN.md](docs/DESIGN.md) for
UI patterns, [DEPLOY.md](docs/DEPLOY.md) for configuration, and
[NEW_PRODUCT.md](docs/NEW_PRODUCT.md) to start a product with `bin/rename`.
