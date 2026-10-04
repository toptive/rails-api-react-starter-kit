# Architecture

Rails is a JSON API at the repository root, with one Vite React SPA in `frontend/`.
PostgreSQL backs application data, Solid Queue, Solid Cache and Solid Cable. Development
and production have dedicated primary/cache/queue/cable databases; tests use the same schema
layout with test-specific adapter behavior.

## Request boundary

`ApplicationController` wraps actions in the request locale, normalizes camelCase input,
and verifies Pundit authorization. Each REST action authorizes or explicitly opts out,
casts input, delegates to one model call and serializes its result. `Api::V1::BaseController`
authenticates a bearer token before actions; its lookup seam returns nil until Session exists.
Never accept arbitrary bearer strings as authentication.

`render_data` uses Alba and emits `{ data, meta }`. `render_collection` counts a relation,
clamps page/perPage, applies limit/offset and adds `meta.pagination`. Domain refusals raise
`ApiError`; the boundary converts Pundit denial, missing/invalid records, missing params and
invalid JSON into the same translated error envelope. Invalid record field names are camelCase
and their values are translation keys. Messages are resolved again in the request locale
when a rescue runs after the around callback has unwound.

`/up` uses Rails' own health controller. `/api/v1/health` is public, explicitly skips
Pundit authorization and uses `HealthSerializer`. Neither route requires domain tables.

## Domain ownership

Models own business rules and instantiate helpers under `app/models/<model>/`.
No services/poros/errors/forms directories. Policies deny every action by default;
tenant records require organization scoping. Controllers never perform SQL or transactions.
Jobs perform exactly one model-method call, on queue `default` or `marketing`.
`Archspec.rb` enforces boundaries and forbidden calls; Prism-based Minitest guards check
method bodies, authorization, response envelopes and queue configuration.

## Infrastructure

`config/queue.yml` declares only default/marketing workers. `config/recurring.yml` is the
home for recurring work. Schema files for Solid adapters are committed under `db/`;
`db:prepare` loads them into the dedicated databases. Action Cable's base classes are kept
for later authenticated channels; no public application channel is exposed.

Mission Control Jobs is mounted at `/jobs` using `OperationsAccess`. Its live-session lookup
is a deny-by-default seam. When the session domain implements it, access requires a live
superadmin session with no impersonator. The engine uses `ActionController::Base` for HTML
and Propshaft for dashboard assets; it does not inherit the JSON API's callbacks.
