# StarterKit — rulebook

Rails 8.1 JSON API on Ruby 3.4.10, PostgreSQL, one React SPA with TanStack Router and
React Query. The API is at the repository root; the SPA lives in `frontend/` and supports
Capacitor. This is the Toptive base template for API products.

One `package.json` and one `pnpm-lock.yaml` at the root. Frontend commands run from the root:
`pnpm dev`, `pnpm build`, `pnpm typecheck`, `pnpm lint`, `pnpm test`, `pnpm i18n:build`.
Never add a second package manifest or workspace package. `pnpm-workspace.yaml` holds
build-script approvals only and declares no packages.

## Non-negotiables

- **This file is the rulebook, not a log.** Never add dated notes, progress, feature walkthroughs
  or lists of files touched. Knowledge about an area belongs in `docs/<AREA>.md`. Change a
  rule only when the architecture decision changes. `AGENTS.md` is a symlink to this file.
- **No plans, trackers, status or research documents in the repository.** Scratch work belongs
  under `/tmp`; `docs/` holds developer reference documentation only.
- **Everything is English**: identifiers, code, comments, docs and commit messages.
- **Tenant isolation.** Every tenant row carries `organization_id`; every query is scoped to
  the caller's organization. Every tenant model needs an isolation test and a Pundit policy.
- **The serializer is the type contract.** Responses go through Alba; TypeScript types and
  API route helpers are generated and committed. Never hand-write a mirror or API path.
- **Gates are green before every commit and push.** Fix the code, never weaken a gate or
  create a baseline of architecture violations.
- **Use rvm's installed Ruby 3.4.10.** Start shells with
  `source ~/.rvm/scripts/rvm && rvm use 3.4.10`. Never compile Ruby or install it in this repo.

## Language rules (STRICT)

- UI and backend text comes only from `i18n/translations.csv` (`key,en,es`). React uses
  `t("namespace.key")`; Rails uses `I18n.t`. Generated JSON and YAML are never hand-edited.
- Add keys in English and Spanish, then run `pnpm i18n:build` (also `bin/rails i18n:build`).
  CSV placeholders are `{{name}}`; the Rails builder converts them to `%{name}`.
- Locale is constrained to available CSV locales. Every action runs inside `I18n.with_locale`;
  query `locale` takes precedence over `Accept-Language`, with region tags falling back to
  their base language. Default is English. Emails use the recipient's locale.
- Error codes are stable English identifiers; messages are translated. Validation details
  carry translation keys, never strings hard-coded in controllers or models.
- The admin translation domain must preserve runtime edits when it synchronizes new CSV
  keys. Generated catalogues supply the default runtime values.

## Layout

```
app/controllers/api/v1/     REST endpoints; authenticate, authorize, cast, delegate, serialize
app/models/                domain rules + POROs under app/models/<model>/
app/serializers/            Alba + Typelizer: the response type contract
app/policies/               Pundit; deny by default
app/jobs/                   one model call per perform
app/channels/               Action Cable; domain calls, no business rules
config/queue.yml            Solid Queue workers: default and marketing only
config/recurring.yml        recurring job declarations
Archspec.rb                 executable backend boundaries
frontend/                   index.html, Vite, TS, ESLint, src/
frontend/src/api/            shared API client, React Query hooks
frontend/src/api/generated/ serializers and route helpers; committed, never hand-edited
i18n/                       translations.csv → locales/*.json + config/locales/*.yml
docs/                       developer reference by area
```

## Backend — Rails API (STRICT)

### Controllers

- REST actions only: `index`, `show`, `create`, `update`, `destroy` (the HTTP DELETE action).
  Another verb is a nested resource, such as `ImpersonationsController#create`.
- Keep controllers skinny: authorize → cast params → ONE model call → render. Models own
  decisions and orchestration; controllers never build SQL, join tables or open transactions.
- Every action explicitly calls Pundit `authorize` or `skip_authorization`; the inherited
  `verify_authorized` callback and architecture tests enforce this. Public actions opt out
  explicitly; authenticated actions never infer authorization from authentication.
- Use `render_data(record, serializer:)` or `render_collection(scope, serializer:)`.
  Raw `render json:` exists only in `ApplicationController`, which owns both envelopes.
- API routes live under `namespace :api { namespace :v1 }`. Use resource trees and Rails
  resource routing; never put a custom action name in an endpoint.
- Raise `ApiError.<status>(:code, details)` for domain refusals. The boundary maps Pundit
  denial to 403, missing records to 404, invalid records to 422, malformed input to 400.
- `Api::V1::BaseController#authenticate!` consumes opaque bearer tokens by checking
  their digest, expiry and revocation in the sessions table.

### Models and business rules

- No `app/services`, `app/poros`, `app/errors` or `app/forms`. Domain errors are model-layer
  objects; helpers are nested under their owning model.
- Models orchestrate their own POROs. Controllers, jobs and channels call the model's public
  API; only models instantiate helpers. Serializers may present a helper's result.
- Top-level model files may be domain objects without tables. Their helper classes still live
  under the owning model's directory, and their tests mirror that directory under `test/models/`.
- UUID primary and foreign keys, integer cents for money, ISO-8601 UTC timestamps, lower-case
  enum values. Strong params stay in controllers; validations stay in models.
- Tenant scoping is mandatory even for lookups by UUID. A supplied organization id never
  establishes authority; membership and policies do.

### Jobs and infrastructure

- `perform` is ONE model-method call. No branching, orchestration, PORO construction or
  controller APIs in jobs. Tests require `default` or `marketing` as the queue.
- Solid Queue, Solid Cache and Solid Cable use PostgreSQL in development and production.
  Recurring jobs live in `config/recurring.yml`; never add an undeclared worker queue.
- Mission Control Jobs is mounted at `/jobs`, behind a live, non-impersonating
  superadmin session constraint. Browser access uses a short-lived signed dashboard cookie.
- The dashboard uses Propshaft for its assets; the SPA uses Vite. Do not move SPA assets
  into Rails views or add a second frontend application.

### Wire conventions

- `/api/v1`, camelCase in both directions, flat request objects, bearer auth without cookies.
  The base boundary normalizes request keys; Alba transforms response attribute names.
- Success `{ "data": ..., "meta": ... }`; failure `{ "error": { "code", "message", "details" } }`.
  Collection pagination is `meta.pagination` with `page`, `perPage`, `total`, `totalPages`.
- Policies deny by default. Superadmin resources answer 404 for everyone else.
- Public endpoints that perform work use Rails `rate_limit`; refusals use the error envelope.
  Health probes are read-only and do not consume a rate-limit budget.

## Type contract

`app/serializers/**` → Typelizer → `frontend/src/api/generated/serializers/`.
`config/routes.rb` → Typelizer → `frontend/src/api/generated/routes/` (only `/api/v1/`).

- Include `ApplicationSerializer` in every serializer. It supplies Alba, lower-camel keys
  and the Typelizer DSL. Give block attributes explicit types; use model constants for enums.
- Run `bin/rails typelizer:generate` after serializer or route changes, review and stage output.
  `bin/rails contract:check` regenerates and fails on drift from the Git index, including stale
  files and untracked output. Generated files are part of the commit.
- Responses use generated interfaces. Runtime input validation is separate; never mirror a
  serializer with a handwritten TypeScript interface or response schema.
- Use generated route definitions through the shared API client. Never hard-code API paths.
  Details: [docs/TYPE_CONTRACT.md](docs/TYPE_CONTRACT.md).

## Frontend — React SPA

- React, TypeScript strict and Vite. The shared SPA uses TanStack Router for navigation and
  React Query for server state.
- Data comes through `frontend/src/api/` hooks and the shared HTTP client; no raw `fetch` or
  axios in pages, no `useEffect` to load data. The client owns bearer and locale headers.
- Input schemas validate forms; generated interfaces type responses. Avoid duplicated server
  state and hand-written route strings. A pending background refresh should keep cached data.
- We own shared components under `components/ui/`. Change repeated visuals there, rather
  than copying classes between pages. Theme tokens only; no literal hex colours in components.
- All files and folders use kebab-case. Pages and hooks have meaningful domain names.
- Every visible string uses translations, including labels, empty states, errors and loading text.

## UX rules

1. Use plain language; technical details belong behind a disclosure.
2. Screens follow user tasks, not database tables. Group related models when users think of
   them as one thing.
3. Larger forms use steps with progress, back navigation and a review step.
4. Explain why information is needed beside the field. Every state offers a clear next step.
5. Destructive actions confirm and state the consequence.
6. Mobile first: tap targets at least 44 px, visible focus and respect for reduced motion.

## Security

- Pundit and tenant scoping on every protected endpoint. Opaque bearer tokens are stored as
  digests, checked for expiry; impersonation never grants superadmin or sudo authority.
- CORS allows the configured SPA origin and Capacitor origins; no cookie credentials.
  Production uses HTTPS and HSTS. Never trust arbitrary proxy headers for client identity.
- No secrets in Git, source, logs or generated assets. Configure env vars and Kamal secrets;
  use `cred` for local credentials. `.env.example` contains placeholders only.
- Brakeman, bundler-audit and pnpm audit are gates. Fix findings; a proven false positive
  needs an individual documented reason, never a blanket suppression.
- Private uploads require authentication, allow-lists, size checks and byte validation.
  Sentry must omit request bodies, bearer tokens and personally identifying fields.

## Testing & gates

`bin/check` runs RuboCop, Archspec, Brakeman, bundler-audit, Minitest, contract and translation
checks, frontend typecheck, ESLint, Vitest and pnpm audit. All failures block completion.

- No CI. `.githooks/pre-commit` checks staged file paths; `.githooks/pre-push` runs `bin/check`.
  `bin/setup` installs the hooks with `git config core.hooksPath .githooks`.
- `.claude/hooks/architecture-check` runs after Edit/Write through `.claude/settings.json`.
  It checks architecture/style and regenerates relevant types or translations immediately.
- More end-to-end tests, fewer unit tests. Backend request tests through the real router,
  authentication, policies, database, serializers and envelope are the default: test each
  endpoint outcome and flows that chain endpoints. Model tests cover real branching only
  (money, dates, policies, parsers); never private helpers, isolated serializers or getters.
- SPA flows use Playwright in `frontend/e2e/` against the real backend (`pnpm e2e` boots
  the test API and seeds). Cover feature flows; mock provider HTTP boundaries only. Vitest
  covers pure functions, never component renders with mocked APIs.
- Architecture tests enforce the rulebook, including no `PLAN.md`, `STATUS.md`, `TODO.md`,
  `NOTES.md`, `REPORT.md` or `tasks/` in the repository.
- Every behavior gets meaningful tests. Architecture tests enforce REST actions, explicit
  authorization, envelopes, model ownership and jobs with one model call.
- Generated files are staged before drift checks. Do not skip hooks to make a commit pass.
  Details: [docs/GATES.md](docs/GATES.md).

## Deploy

Kamal configuration lives in `config/deploy.yml`; Docker uses the same Ruby as `.ruby-version`.
Run gates before building. Propshaft dashboard assets are precompiled in the image; database
schemas are prepared at server boot. Supply secrets through environment variables, never baked
files. Never run setup or seeds against production. See [docs/DEPLOY.md](docs/DEPLOY.md).

## Domain documents

| Area | Doc | Owns |
|---|---|---|
| Architecture | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | boundaries, responses, policies, jobs, infrastructure |
| Gates | [docs/GATES.md](docs/GATES.md) | checks, hooks, setup |
| i18n | [docs/I18N.md](docs/I18N.md) | CSV, generated catalogues, request locale |
| Type contract | [docs/TYPE_CONTRACT.md](docs/TYPE_CONTRACT.md) | Alba, generated types and route helpers |
| Deploy | [docs/DEPLOY.md](docs/DEPLOY.md) | Docker, Kamal and environment variables |
