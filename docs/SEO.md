# SEO infrastructure

The SPA owns page markup and head metadata. The backend serves GET `/sitemap.xml` and
GET `/robots.txt`; proxy these paths from the public SPA server when API and SPA origins
are separate. `PUBLIC_URL` supplies the public base URL, defaulting to `SPA_ORIGIN`.

## Sitemap and robots

The sitemap contains the home page and currently published legal slugs, in every CSV
locale. English uses unprefixed URLs; Spanish uses `/es` and `/es/legal/<slug>`. Every
entry lists xhtml alternate links for every locale. Draft legal documents are excluded.
XML URL values are escaped. A locked sitemap remains a valid empty urlset.

Robots has a wildcard group and individual groups for Googlebot, Bingbot, OAI-SearchBot,
ChatGPT-User, Claude-SearchBot, Claude-User, PerplexityBot and Perplexity-User. Training
groups GPTBot, ClaudeBot, Google-Extended and CCBot permit indexing only when listed in
`config.x.allowed_training_bots` (all four by default).

Every allowed group repeats private paths, including locale-prefixed variants:
admin, API, dashboard, onboarding, settings, session, registration, magic links,
invitations, auth, email subscriptions, organization creation, sudo and error screens.
Contract §6.1 paths are explicitly included. Robots always ends with
`Sitemap: PUBLIC_URL/sitemap.xml`.

## Indexing lock and canonical host

`SITE_INDEXING=0` locks indexing. Production defaults locked; development/test default
unlocked. While locked, robots disallows everything, sitemap is empty, and middleware
adds `X-Robots-Tag: noindex, nofollow` to every response, including static files and errors.
The SPA should mirror the lock in its page robots metadata when deploying a product.

`CANONICAL_HOST` (defaults to the public URL host in production) redirects alternate public hosts to the configured public URL
with the same path/query: 301 for GET/HEAD and 308 for other methods. The explicit API
origin remains usable on split-origin deployments. GET `/health` always bypasses the
redirect. Configure the SPA's public web server consistently for routes it serves itself.

See [DEPLOY.md](DEPLOY.md) for environment and proxy configuration.
