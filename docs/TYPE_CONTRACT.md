# Type contract

Alba serializers and Rails routes generate the shared SPA contract with
`bin/rails typelizer:generate`. Output under `frontend/src/api/generated/{serializers,routes}`
is committed. `bin/rails contract:check` deletes stale output, regenerates it and compares it
to the Git index. Stage generated changes before running gates. Never edit generated files
or hand-write response mirrors or API paths.

Every serializer includes `ApplicationSerializer`, which supplies Alba, lower-camel keys
and Typelizer. Computed attributes declare `typelize` types explicitly. Nullable values are
sent as null; optional fields may be omitted. Dictionaries keep their keys. `FieldError`,
`ApiErrorBody`, `Pagination` and generic `Envelope<T, M>` come from backend declarations,
just like domain responses. Pagination uses `meta.pagination.perPage`.

Route groups use controller paths that match URL resources, preserving plural names:
`apiV1AuthMagicLinks`, `apiV1AuthMagicLinksSessions`,
`apiV1AdminLegalDocumentsVersionsPublication`. Singleton groups retain singular names such
as `apiV1Bootstrap` and `apiV1SettingsBilling`; the session sign-in/sign-out endpoints share
`apiV1AuthSessions`. Actions are `index`, `show`, `create`, `update`, `destroy`.
Files follow `routes/Api/V1/<Namespace>/<Controller>Controller.ts`, with default exports and
an `index.ts`. The runtime exports `setBaseUrl`, `Method`, `RouteOptions` and
`RouteDefinition { url, method }`. Required parameters are positional in URL order, followed
by optional `{ query }` options.

`lib/type_contract.rb` adapts Typelizer 0.14's route template to positional arguments,
re-exports runtime types, and emits the envelope's generic declaration. Controller paths
supply group names; no group alias map or manual frontend helper is needed. The generator
includes `/api/v1` only; SPA delivery, test mailbox, webhook and jobs browser routes stay
outside it. `/api/v1/auth/google/start` and callback are browser navigation endpoints;
all other SPA data calls use generated definitions through the shared HTTP client.

After a serializer or route change, regenerate, review the output, stage it, and run
`pnpm typecheck`, `pnpm lint`, `pnpm test` and `bin/check`. Database-backed inference needs
a migrated development database. TypeScript interfaces belong to the generator; input
validation remains in the SPA's Zod schemas.
