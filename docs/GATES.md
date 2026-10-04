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
in the envelope, no service folders, one model call per job and declared worker queues.
Behavior tests verify the boundary's localized errors, bearer refusal and pagination.

## Testing

More end-to-end tests, fewer unit tests. Backend request tests through the real router,
  authentication, policies, database, serializers and envelope are the default: test each
  endpoint outcome and flows that chain endpoints. Model tests cover real branching only
  (money, dates, policies, parsers); never private helpers, isolated serializers or getters.
- SPA flows use Playwright in `frontend/e2e/` against the real backend (`pnpm e2e` boots
  the test API and seeds). Cover feature flows; mock provider HTTP boundaries only. Vitest
  covers pure functions, never component renders with mocked APIs.
- Architecture tests enforce the rulebook, including no `PLAN.md`, `STATUS.md`, `TODO.md`,
  `NOTES.md`, `REPORT.md` or `tasks/` in the repository.
