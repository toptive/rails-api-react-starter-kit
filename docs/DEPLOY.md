# Deploy

Kamal 2 deploys one Rails + SPA image to the shared Toptive server. Infrastructure is
shared: the `kamal` Docker network, Postgres and kamal-proxy. The app owns its role,
databases and storage volume. Provisioning is in [NEW_SERVER.md](NEW_SERVER.md);
product setup is in [NEW_PRODUCT.md](NEW_PRODUCT.md).

## Image and boot

The Dockerfile adapts helperflow's Rails image and native remote builder conventions:

1. Node 24 installs the exact pnpm version in the root `package.json` with a frozen
   lockfile. `pnpm build` builds and prerenders the SPA into `public/` through `VITE_OUT_DIR=../public`.
2. Ruby 3.4.10 installs production gems, precompiles Bootsnap and the Propshaft assets
   used by Mission Control Jobs. Build-time dummy settings require no database or secret.
3. The Bookworm slim runtime copies only Rails runtime files, production gems and built `public/`, and runs as UID/GID 1000 through
   Thruster on port 80. Puma listens on 3000. Node and compiler tools stay in build stages.
   Gem test/docs directories, Sorbet annotations, build objects and other Ruby ABIs are removed;
   native gem binaries are stripped. PostgreSQL client binaries are copied directly, avoiding
   the distribution's Perl version wrapper. App Bootsnap caches are precompiled; asset
   compilation warms the gem caches used at boot.

The kit stores and validates uploads without image transformations, so the runtime omits
libvips. Products adding Active Storage variants must install that image-processing library
in the runtime stage.

`bin/docker-entrypoint` runs `db:prepare` → `i18n:sync` → Thruster/Puma. Either task failing
stops the container. Production disables the Rails seed path, including the implicit seed
inside `db:prepare`; never run setup or seeds on production. One-off commands bypass these
tasks. Runtime translation edits live in PostgreSQL and survive synchronization and deploys.

Kamal builds committed `HEAD`, not the working tree. `.dockerignore` excludes keys, encrypted
credentials, dotenv files, Git metadata, node_modules and local data. Production uses runtime
`SECRET_KEY_BASE`; no master key is required. Never pass secrets as Docker build arguments.

### Reproduce the local smoke test

Use disposable fixture values only. These names and port must be free; do not substitute
an existing product database. The fixture role is a superuser only inside this throwaway
container so Rails can create its databases; real production roles are restricted.

```sh
source ~/.rvm/scripts/rvm && rvm use 3.4.10
docker build -t starter_kit:local .
docker network create starter-kit-smoke
docker run -d --name starter-kit-smoke-db --network starter-kit-smoke \
  -e POSTGRES_USER=starter_kit -e POSTGRES_PASSWORD=local_fixture postgres:17
until docker exec starter-kit-smoke-db pg_isready -U starter_kit; do sleep 1; done
docker run -d --name starter-kit-smoke-app --network starter-kit-smoke \
  -p 127.0.0.1:4480:80 \
  -e DB_HOST=starter-kit-smoke-db -e STARTER_KIT_DATABASE_PASSWORD=local_fixture \
  -e SECRET_KEY_BASE=local_fixture_local_fixture_local_fixture_local_fixture_local_fixture \
  -e SPA_ORIGIN=http://localhost:4480 -e API_ORIGIN=http://localhost:4480 \
  -e PUBLIC_URL=http://localhost:4480 -e SITE_INDEXING=0 \
  -e SOLID_QUEUE_IN_PUMA=true -e RAILS_MAX_THREADS=5 starter_kit:local
# Wait for migrations and i18n sync, then expect HTTP 200 and status ok.
for attempt in $(seq 1 60); do
  if curl -fsS http://localhost:4480/health; then break; fi
  sleep 1
done
curl -f -i http://localhost:4480/health
curl -f -I http://localhost:4480/
docker logs starter-kit-smoke-app
docker exec starter-kit-smoke-app id
docker image inspect starter_kit:local --format '{{.Architecture}} {{.Size}} bytes'
docker rm -fv starter-kit-smoke-app starter-kit-smoke-db
docker network rm starter-kit-smoke
```

The native arm64 runtime is approximately 287 MiB unpacked (301,124,737 bytes).
Image size depends on architecture and base-image updates; measure the unpacked image with
`docker image inspect` above. Build locally without `--platform` for the native smoke test.
Production uses a native amd64 remote builder, avoiding QEMU on an Apple-silicon laptop.

## First deploy

1. Run `bin/rename` and provision the role/databases, DNS and private upload bucket using
   [NEW_SERVER.md](NEW_SERVER.md). Replace every `CHANGE_ME` in `config/deploy.yml`.
2. Keep the domain's A record pointing at the selected server; allow inbound 80/443 for
   kamal-proxy and ACME. With Cloudflare, use DNS only initially and Full (strict) if proxied
   later. Do not enable `forward_headers` without restricting who may reach the origin.
3. Inspect `docker network inspect kamal` on the server; set `TRUSTED_PROXY_CIDRS` to its
   actual subnet. The config deliberately has no guessed trusted subnet.
4. Store fresh secrets with `cred add`: `starter_kit/SECRET_KEY_BASE` and
   `starter_kit/STARTER_KIT_DATABASE_PASSWORD` (the project/name change after rename).
   Add provider keys only when enabling those integrations. `.kamal/secrets` is committed
   **references only**, populated by `cred exec`; never replace references with values.
5. Review and stage generated contracts/locales, run `bin/check`, commit all changes, and
   start from a clean tree. The executable `.kamal/hooks/pre-build` runs the complete gate
   with production secrets and connection variables removed. It always checks; this kit
   does not emit a gate stamp. No skip flag and no pre-deploy hook are used.
6. With the native builder configured, run locally:

   ```sh
   source ~/.rvm/scripts/rvm && rvm use 3.4.10
   cred exec starter_kit/SECRET_KEY_BASE starter_kit/STARTER_KIT_DATABASE_PASSWORD -- bundle exec kamal setup
   curl -f https://CHANGE_ME.toptive.dev/health
   ```

   Enable optional references in both `.kamal/secrets` and `env.secret`, and include their
   `project/NAME` arguments in `cred exec`. The loopback registry needs no authentication;
   its required Kamal login uses a dummy password. Do not run `kamal config` with live
   secrets in a terminal capture: it can display resolved values.

The proxy terminates TLS; Rails assumes SSL, keeps HTTPS/HSTS enabled and exempts `/health`
and `/up` from redirects. `/health` checks the database, bypasses canonical-host redirects
and sends `no-store`. HTML revalidates after deployment; fingerprinted assets are served
through Thruster and retained by Kamal's `asset_path` across rolling deployments.

The SPA bundle is served from `public/index.html`. `SpaDelivery` runs before Rails static
serving, serves prerendered public pages, and falls back to `index.html` for browser routes.
HTML uses private/no-store caching with a nonce for the inline appearance bootstrap;
fingerprinted assets cache for a year. Unknown `/api/*` routes use the JSON error envelope,
and `/admin/jobs`, health, sitemap, robots and webhooks remain backend routes.

Docker/Kamal build arguments `VITE_API_URL`, `VITE_PUBLIC_URL`, `VITE_SITE_INDEXING` and
optional `VITE_PRERENDER_API_URL` configure the bundle. Same-origin API calls are the default.
A reachable prerender API includes published legal pages; otherwise those pages load through
the API at runtime. Set both `SITE_INDEXING` and `VITE_SITE_INDEXING` to `1` at launch.

## Database and workers

Use one shared PostgreSQL **server**, not a new database accessory for each app. Unlike the
Phoenix kit's single database, this Rails kit currently declares `starter_kit_production`,
`starter_kit_production_cache`, `starter_kit_production_cable` in `config/database.yml`. Pre-create all three for the same
restricted app role so `db:prepare` needs no `CREATEDB` privilege.

Solid Queue uses the **primary connection** so webhook inbox writes and enqueueing share
one transaction. Cache and Cable use their named connections. Do not redirect
all connection URLs to one database: their schema loaders are independent.

`SOLID_QUEUE_IN_PUMA=true` starts workers for `default` and `marketing`; `false` leaves them
off. Start with one Puma process (`WEB_CONCURRENCY=0`) and one queue worker process. The
400 MB cap is a starting limit, not a measured Rails capacity promise: monitor web, queue,
cache and Cable connections and RSS before increasing concurrency or packing more apps.

## Routine deploy, rollback and staging

```sh
bin/check
# Commit first, then wrap each Kamal call with the same cred exec arguments as setup.
cred exec starter_kit/SECRET_KEY_BASE starter_kit/STARTER_KIT_DATABASE_PASSWORD -- bundle exec kamal deploy
curl -f https://CHANGE_ME.toptive.dev/health
```

Use `bundle exec kamal logs`, `kamal console`, `kamal app details` and
`kamal rollback <version>` under that same credential wrapper. A failed migration or i18n
sync fails the new health check while the old version keeps serving. Keep migrations
backward compatible: image rollback does not reverse database changes. Verify `/health`,
SPA sign-in, an enqueued job, private uploads and mail after enabling those providers.

Staging uses `RAILS_ENV=production` with a separate destination file, service/domain,
databases/role, bucket, secret key and provider test credentials. Follow helperflow's
separate-host pattern if possible; never use production data. Keep `SITE_INDEXING=0` and
billing off or in test mode. `MAIL_ALLOWED_RECIPIENTS` currently filters invitations only
outside production; it is **not** a staging SMTP safety boundary. Use a sandbox mail provider.

Never remove the shared proxy, registry, network or Postgres to remove an app. Back up all
of the app's databases, and scope rollback/removal to that app's containers and volumes.

## Environment inventory

Audit all forms, including computed names (not just `ENV["literal"]`):

```sh
rg -n 'ENV\[' app lib config
rg -n 'ENV\.fetch|env:' app lib config
rg -n 'process\.env|import\.meta\.env' frontend i18n
```

| Variable | Default / purpose |
|---|---|
| `RAILS_ENV`, `RACK_ENV` | Runtime environment; production in Docker; development/test locally |
| `APP_NAME` | `StarterKit`; product name in bootstrap and mail |
| `SPA_ORIGIN`, `API_ORIGIN` | Both required in production; browser CORS/mail and API handoff origins |
| `PUBLIC_URL`, `CANONICAL_HOST` | Public links/SEO; default to SPA origin and its host in production |
| `TENANCY` | `multi` or `single`; default `multi` |
| `SIGNUP_MODE` | `open`, `invite`, `closed`; deploy starts with `invite` |
| `SITE_INDEXING` | Deploy `0`; set `1` at launch for robots/sitemap/indexing |
| `TRUSTED_PROXY_CIDRS` | Empty by default; comma-separated networks allowed to supply client identity |
| `DB_HOST`, `STARTER_KIT_DATABASE_PASSWORD` | Production PostgreSQL host (`localhost`) and app-role password |
| `DATABASE_URL`, `PRIMARY_DATABASE_URL` | Rails primary connection overrides; use only deliberately |
| `CACHE_DATABASE_URL`, `CABLE_DATABASE_URL` | Rails named connection overrides |
| `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`, `PGSERVICE`, `PGSERVICEFILE`, `PGOPTIONS` | libpq connection settings, useful for isolated local gates |
| `SECRET_KEY_BASE` | Required production signing secret; fresh per product/environment |
| `RAILS_MASTER_KEY` | Only for credentials in a custom image; stock image excludes encrypted credentials |
| `SECRET_KEY_BASE_DUMMY` | Build-only bypass for asset compilation; never set at runtime |
| `PORT`, `RAILS_MAX_THREADS` | Puma port (3000), thread/pool size (deploy 5) |
| `WEB_CONCURRENCY`, `JOB_CONCURRENCY` | Puma process count (deploy 0 = single mode), queue worker processes (1) |
| `SOLID_QUEUE_IN_PUMA`, `PIDFILE` | Literal `true` starts queue supervisor; optional Puma PID file |
| `RAILS_LOG_LEVEL` | `info`; production logging level |
| `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_AUTHENTICATION` | Mail server, port 587, authentication `plain`; STARTTLS enabled |
| `SMTP_USERNAME`, `SMTP_PASSWORD` | Mail credentials; secrets |
| `MAIL_FROM`, `MAIL_FROM_NAME` | `hello@example.com`, app name; sender defaults |
| `MAIL_FROM_EN`, `MAIL_FROM_ES`, `MAIL_FROM_NAME_EN`, `MAIL_FROM_NAME_ES` | Optional per-locale sender overrides (`MAIL_FROM_<LOCALE>` / `MAIL_FROM_NAME_<LOCALE>`) |
| `MAIL_ALLOWED_RECIPIENTS` | Comma-separated addresses or `*@domain`; non-production invitation filter only |
| `BILLING_ENABLED`, `BILLING_MODE` | `false`, `test`; enable deliberately with `test` or `live` credentials |
| `BILLING_RENEWAL_NOTICES`, `BILLING_TEST_OPERATOR_USER_IDS` | Off; comma-separated operator UUIDs (superadmins also qualify) |
| `STRIPE_TEST_SECRET_KEY`, `STRIPE_LIVE_SECRET_KEY` | Mode-specific Stripe secret key |
| `STRIPE_TEST_WEBHOOK_SECRET`, `STRIPE_LIVE_WEBHOOK_SECRET` | Mode-specific webhook signing secret |
| `STRIPE_TEST_PRICE_PRO_MONTHLY`, `STRIPE_TEST_PRICE_PRO_YEARLY` | Test offer price IDs; computed pattern `STRIPE_<MODE>_PRICE_<OFFER_ID>` |
| `STRIPE_LIVE_PRICE_PRO_MONTHLY`, `STRIPE_LIVE_PRICE_PRO_YEARLY` | Live offer price IDs |
| `TURNSTILE_REQUIRED`, `TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY`, `TURNSTILE_HOSTNAME` | Off; public widget key, verification secret, expected hostname (defaults to public URL host) |
| `S3_BUCKET`, `S3_ENDPOINT`, `S3_REGION` | Private upload bucket; endpoint defaults to `https://s3.amazonaws.com`, region `us-east-1` |
| `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | Upload bucket credentials |
| `POSTHOG_API_KEY`, `POSTHOG_HOST` | Optional analytics; an HTTPS host is required with the key |
| `OPENROUTER_API_KEY`, `OPENROUTER_MODEL` | Optional AI/translation fills; model `openai/gpt-4o-mini` |
| `FAL_KEY`, `GOOGLE_API_KEY`, `GEMINI_MODEL` | Optional media/Gemini; model `gemini-2.5-flash` |
| `SENTRY_DSN`, `SENTRY_ENV`, `KAMAL_VERSION` | Optional monitoring, Rails environment default, deployment release |
| `KAMAL_REGISTRY_PASSWORD` | Dummy login for loopback registry; real secret with an authenticated registry |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | Optional Google OAuth credentials; configure both together |
| `NATIVE_SCHEME` | Google native handoff scheme; defaults to `starterkit` and must match the Capacitor app |
| `VITE_DEV_API_URL`, `VITE_PORT` | Vite dev proxy target `http://localhost:3000`, SPA port 5173 |
| `VITE_API_URL`, `VITE_PUBLIC_URL`, `VITE_SITE_INDEXING`, `VITE_PRERENDER_API_URL`, `VITE_OUT_DIR` | Public bundle/prerender configuration; Docker build args, output `../public` |
| `E2E`, `E2E_PGDATABASE`, `E2E_API_DIR`, `E2E_API_URL`, `E2E_BASE_URL`, `E2E_PORT`, `E2E_VITE_PORT`, `E2E_API_OFF_URL`, `E2E_BASE_OFF_URL`, `E2E_STRIPE_URL`, `E2E_MAILBOX_PATH`, `E2E_AI`, `E2E_BILLING` | Test-only browser runner controls; see [GATES.md](GATES.md) |
| `OBJC_DISABLE_INITIALIZE_FORK_SAFETY`, `HTTPS_PROXY`, `HTTP_PROXY` | macOS fork safety and optional audit network proxy; see [GATES.md](GATES.md) |
| `BUNDLE_GEMFILE`, `BUNDLE_PATH`, `BUNDLE_WITHOUT`, `BUNDLE_DEPLOYMENT` | Bundler boot/deployment controls; supplied by Docker |
| `LD_PRELOAD` | Docker's jemalloc library path |
| `CI` | Enables eager loading in test; no CI service is configured |
| `PARALLEL_WORKERS` | Linux Rails test workers (2); macOS and catalogue/Cable gates use 1 |

Provider readiness stops production boot when enabled billing, Turnstile or PostHog has
missing/inconsistent settings. Uploads and AI report not-configured when their credentials
are absent. Google sign-in is enabled when its OAuth client credentials are configured;
`GOOGLE_API_KEY` above is for Gemini. See [PLATFORM.md](PLATFORM.md), [BILLING.md](BILLING.md)
and [AUTH.md](AUTH.md) before enabling providers.
