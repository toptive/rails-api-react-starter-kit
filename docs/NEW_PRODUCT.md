# From template to product

1. Create a private repository from `toptive/rails-api-react-starter-kit` and clone it.
2. Activate Ruby and rename the product:
   ```sh
   source ~/.rvm/scripts/rvm && rvm use 3.4.10
   bin/rename --app acme_app --module AcmeApp --name "Acme" --domain acme.test
   bin/setup --skip-server
   ```
   Rename rewrites the Rails module, database names, root package name, SPA storage prefix
   (including the inline appearance bootstrap), Docker build domains and Kamal service,
   image, environment and host. It regenerates locales; setup generates the contract after creating the databases. `--dry-run` lists
   each changed file and the change count without writing; `--help` shows the options.
   Generated contracts, locale catalogues and lockfiles are excluded from replacement.
   Encrypted credentials and ignored keys are regenerated
   without decrypting the template, and the local development signing secret is removed.
   Production uses a separate runtime `SECRET_KEY_BASE`. No infrastructure or production data
   is changed.
3. Choose `TENANCY=multi` or `single`. Change copy in `i18n/translations.csv`, theme tokens in
   `frontend/src/styles/theme.css`, the logo and static branding under `public/`. Review mail
   sender settings and the shared mail layout. See [DESIGN.md](DESIGN.md).
4. Run `pnpm i18n:build`, `bin/rails typelizer:generate`, and `pnpm build`. Stage generated
   files before `bin/check`; every gate, including the 31 browser journeys reported by
   Playwright (30 declarations; sudo runs both password and magic link cases), must pass.
5. Start Rails with `bin/dev` and Vite with `pnpm dev` in a second terminal. Choose free API/Vite ports per product; the default
   Vite proxy reaches Rails on 3000. Browser links use `SPA_ORIGIN`; the API uses `API_ORIGIN`.
6. Add product models, policies, serializers, request tests and task-oriented SPA pages.
   Read `CLAUDE.md` first. Keep tenant queries scoped through `Model.for(scope)`.
7. Provision the product's PostgreSQL role and primary/cache/cable databases on shared
   PostgreSQL, configure DNS and fill the server address in `config/deploy.yml`. Configure
   runtime secrets through `cred`; follow [NEW_SERVER.md](NEW_SERVER.md) for provisioning and use environment references in `.kamal/secrets`.
8. Run gates, commit, build the image and deploy with Kamal. The entrypoint prepares schemas
   and synchronizes translations before the server listens. Never run seeds in production.
9. Bootstrap the first administrator with
   `bin/rails runner 'User.bootstrap_superadmin!(email: ENV.fetch("ADMIN_EMAIL"))'` using the
   product's environment. Publish terms, privacy and cookies in the admin area.
10. At launch, set both `SITE_INDEXING` and `VITE_SITE_INDEXING` to `1` in the deploy template.
    Keep them `0` for previews. See [DEPLOY.md](DEPLOY.md) and [SEO.md](SEO.md).
