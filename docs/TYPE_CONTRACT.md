# Type contract

Alba serializers are the response schema. Include `ApplicationSerializer` for lower-camel
keys and the Typelizer DSL; declare explicit types for hash/block attributes. `HealthSerializer`
defines `status` as the TypeScript literal `"ok"`.

`config/initializers/typelizer.rb` generates:

| Source | Output |
|---|---|
| `app/serializers/**/*.rb` | `frontend/src/api/generated/serializers/` |
| Routes beginning `/api/v1/` | `frontend/src/api/generated/routes/` |

```sh
bin/rails typelizer:generate
git add frontend/src/api/generated
bin/rails contract:check
```

The check removes prior output and regenerates both directories, so deleted serializers
cannot leave stale interfaces. It compares generated files against the Git index, including
untracked files. A staged generated update passes before commit; a modified or missing file
fails. After a failure, review regenerated output and stage it with its source change.

Import generated interfaces and route definitions into the shared API client. Never hand-edit
output, mirror a response interface or hard-code a URL. Inputs may have separate validation
schemas; they do not replace the generated response types. `/up`, engine routes and framework
asset routes are excluded from the SPA's API contract.
