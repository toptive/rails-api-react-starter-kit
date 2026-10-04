# Gates

Run `bin/check` from the repository root under rvm Ruby 3.4.10. All gates run even when an
earlier one fails; the command exits nonzero and lists the failures. Never weaken a check.

| Gate | Command |
|---|---|
| Ruby style | `bundle exec rubocop` |
| Boundaries | `bundle exec archspec check` |
| Application security | `bundle exec brakeman --no-pager -q` |
| Gem advisories | `bundle exec bundler-audit check --update` |
| Rails tests | `bin/rails test` |
| Generated API contract | `bin/rails contract:check` |
| Generated locales | `bin/rails i18n:check` |
| TypeScript | `pnpm typecheck` |
| ESLint | `pnpm lint` |
| Frontend tests | `pnpm test` |
| Browser journeys | `bin/e2e` (runs `pnpm e2e`) |
| npm advisories | `pnpm audit --audit-level=high` |

Dependency audits need network access. Review generated changes and stage them before the
contract/locale checks: those compare the regenerated working tree to the index, so they work
both before the first commit and during later commits. `pnpm build` separately verifies the
production SPA bundle.

## Hooks

`bin/setup --skip-server` installs dependencies, prepares dev/test databases and sets
`core.hooksPath=.githooks`. No CI is configured; the local hooks are the gates.

- Pre-commit selects staged Ruby/frontend paths, runs style, Archspec and architecture tests,
  and checks generated contracts or locales when their source/output changes.
- Pre-push delegates to `bin/check`. It clears Git's local environment variables so the
  advisory database can run Git in its own repository.
- Claude PostToolUse (`Edit|Write`) runs `.claude/hooks/architecture-check`, checks relevant
  code and regenerates types or translations. A failure exits 2 with diagnostic output.

Architecture tests enforce REST-only actions, explicit Pundit authorization, raw JSON only
in the envelope, no service folders, one model call per job, declared worker queues and scoped
tenant queries. Every tenant model has a policy and an isolation request test; see
[TENANCY.md](TENANCY.md).
Behavior tests verify the boundary's localized errors, bearer refusal and pagination.

## Testing

More end-to-end tests, fewer unit tests.

- Backend request tests through the real router,
  authentication, policies, database, serializers and envelope are the default: test each
  endpoint outcome and flows that chain endpoints. Model tests cover real branching only
  (money, dates, policies, parsers); never private helpers, isolated serializers or getters.
- SPA flows use Playwright in `frontend/e2e/` against the real backend (`bin/e2e` boots
  the test API, then runs `pnpm e2e`). Cover feature flows; mock provider HTTP boundaries only. Vitest
  covers pure functions, never component renders with mocked APIs.
- Architecture tests enforce the rulebook, including no `PLAN.md`, `STATUS.md`, `TODO.md`,
  `NOTES.md`, `REPORT.md` or `tasks/` in the repository.

Backend tests use an isolated `rails_api_starter_kit_test` database and two workers by default.
Set `PARALLEL_WORKERS` to match available PostgreSQL connection capacity.

On macOS, `bin/check` exports `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` for Rails parallel
workers. `pnpm audit` may require the local network proxy: supply `HTTPS_PROXY` and
`HTTP_PROXY` in the calling shell when the npm advisory service is unreachable directly.

## Browser journeys

`bin/check` and pre-push run `bin/e2e`. It creates three disposable PostgreSQL databases
(primary, cache and cable), boots the test API, runs `pnpm e2e`, stops the API and drops the
databases on success or failure. Existing databases are refused. Test-only mail is shared by
the API and fixture runners through JSON files under ignored `tmp/mailbox/`.

Playwright starts Vite on 5174 and 5175, the Stripe stub on 4242, and the billing-off API on
4101. The main API uses 4100. The stub receives actual Stripe HTTP requests; signed webhooks
reach the real Rails boundary and execute reconciliation. Only Rails test mode accepts that
exact redirect origin. Turnstile is off, AI is unconfigured, and billing is on; all journeys
run with zero skips. Production flags, rate limits and URL allow-lists stay enforced.

`frontend/e2e/backend.ts` is the per-kit fixture seam. `seedUser`, `expireSudo` and
`sendOptionalEmail` use `bin/rails runner`; the first administrator uses
`User.bootstrap_superadmin!`. The billing-off lane starts Rails against the same isolated
database with `BILLING_ENABLED=false`. Tests use ordinary HTTP and real database state.
The E2E lane delivers jobs inline; request tests still exercise transactional Solid Queue
inbox insertion and job persistence.

| Variable | Purpose/default |
|---|---|
| `E2E_PGDATABASE` | Disposable name containing `e2e`; defaults to a process-specific name |
| `E2E_PORT` | Main API port; 4100 |
| `E2E_API_OFF_URL` | Billing-off API; defaults to main port + 1 |
| `E2E_VITE_PORT` | Main Vite port; 5174 |
| `E2E_BASE_URL`, `E2E_BASE_OFF_URL` | Existing SPAs; omit to let Playwright own Vite |
| `E2E_STRIPE_URL` | Stub origin; `http://127.0.0.1:4242` |
| `E2E_API_DIR` | Runner checkout; set by `bin/e2e` |
| `E2E_MAILBOX_PATH` | JSON mailbox; `/dev/mailbox/json` |

Choose distinct databases, API ports, Vite ports and stub ports for parallel products.
`PGHOST`, `PGPORT`, `PGUSER` and `PGPASSWORD` apply to local PostgreSQL. Reports and traces
are ignored under `frontend/playwright-report/` and `frontend/test-results/`.

The shared catalogue audit scans both React and Rails sources. Shared keys retained by the
CSV union have explicit reasons in `i18n/retained-keys.json`; never prune a backend key to
make lint pass. `pnpm i18n:build` produces both JSON and Rails YAML from the same CSV.
