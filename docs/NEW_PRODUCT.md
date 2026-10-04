# From template to product

1. **Create the repository.** Use `toptive/rails-api-react-starter-kit` as a GitHub template,
   create the product repository and clone it. Keep the root package manifest and lockfile;
   `frontend/` is the only SPA, and can later serve Capacitor.
2. **Rename and install**, from the repository root:

   ```sh
   source ~/.rvm/scripts/rvm && rvm use 3.4.10
   bin/rename --app acme_app --module AcmeApp --name "Acme" --domain acme.test --dry-run
   bin/rename --app acme_app --module AcmeApp --name "Acme" --domain acme.test
   bin/setup --skip-server
   ```

   PostgreSQL, Node 22.12+ and the package.json-pinned pnpm must be available. Setup installs
   gems and frontend dependencies, builds locales/types, prepares development/test databases
   and installs Git hooks. It does not start servers with `--skip-server`.

   The script is a one-time operation on tracked text files. It rewrites the Rails namespace,
   database names and role/password variable, package name, Docker image examples, deployment
   names, domain/sender defaults, CSV branding and tests. It handles `starter-kit` prefixes in
   both `frontend/index.html` and `frontend/src/lib/storage-keys.ts` when those files exist.
   Keep them tracked after importing the shared SPA; a product must not reuse another app's
   browser storage. Vendored code, lockfiles, symlinks and generated types/locales are skipped;
   setup rebuilds generated output from its source. Review all changes before committing.

   Encrypted Rails credentials and ignored key files are regenerated, never decrypted or
   copied from the template. Fresh credential files contain only a new signing secret; add
   any product-specific settings deliberately. `tmp/local_secret.txt` is removed so Rails
   regenerates its development secret. Store a separate production `SECRET_KEY_BASE` in
   `cred`; production images do not contain credentials files or keys. Keep generated `.key`
   files and `config/master.key` out of Git and store them securely if you use local credentials.
3. **Choose tenancy.** Set `TENANCY=multi` for separate organizations or `single` for one shared
   organization. Choose `SIGNUP_MODE=open|invite|closed`; production starts with `invite`.
   Read [TENANCY.md](TENANCY.md) before adding tenant rows and policies.
4. **Brand the product.** Replace theme tokens, fonts, logo, favicon and social images in the
   shared SPA. Edit product and landing copy in `i18n/translations.csv`, including `app.name`,
   `home.*` and mail strings. Supply English and Spanish together; never hand-edit generated
   JSON/YAML. Add product-specific email branding through the established mailer conventions.
5. **Regenerate, test and commit.**

   ```sh
   pnpm i18n:build
   bin/rails typelizer:generate
   git add -A
   bin/check
   docker build -t acme-app:local .
   git commit -m "Rename the template to Acme"
   ```

   Review the index before committing, including secret exclusions. Drift checks compare
   generated files with the index, so stage them first. Reproduce the throwaway PostgreSQL
   image smoke in [DEPLOY.md](DEPLOY.md), using the renamed role/password variable. Never
   point rename/setup tests at a production database.
6. **Write legal documents.** Create and publish terms, privacy and cookies through Admin →
   Legal documents before accepting real users; see [ADMIN.md](ADMIN.md). Do not ship template
   legal wording as the product's policy.
7. **Pick development ports.** Run `PORT=3011 bin/dev` and, in a second terminal,
   `API_URL=http://localhost:3011 VITE_PORT=5181 pnpm dev`. Set `SPA_ORIGIN` / `API_ORIGIN` for
   mail/handoff links when using nondefault ports. The renamed database names separate
   products; parallel worktrees of the same product still need isolated database settings.
8. **Build the product.** Read [CLAUDE.md](../CLAUDE.md). Add domain rules to models, REST API
   controllers, Pundit policies and Alba serializers, then generate TypeScript/routes. Put
   API hooks and pages in the shared SPA; test tenant isolation and user flows through the
   real router. Adapt onboarding to the product's first task.
9. **Prepare infrastructure.** Provision the role/databases, private bucket and DNS following
   [NEW_SERVER.md](NEW_SERVER.md). Rename does not provision anything: server IP, proxy subnet
   and bucket remain `CHANGE_ME` until you configure them. Use the real production domain
   rather than the `.test` hostname from the example.
10. **Deploy.** Fill the remaining deployment settings, add credentials with `cred add`, run
    the full gates and commit, then `cred exec ... -- bundle exec kamal setup` as documented
    in [DEPLOY.md](DEPLOY.md). Verify `/health`, the SPA, mail, storage and jobs. Provision the
    first superadmin through a deliberate console/model operation; this branch does not
    supply a bootstrap-admin task or default administrator credentials. Publish legal
    documents before opening registration; never run development seeds in production.
11. **Launch.** Set `SITE_INDEXING: "1"` and `SIGNUP_MODE: open`, then deploy. Until launch,
    keep the indexing lock on; see [SEO.md](SEO.md). Enable billing, Turnstile and analytics
    only after their credentials and provider settings pass readiness checks.
