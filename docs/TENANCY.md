# Organizations and tenancy

`TENANCY` selects `multi` (default) or `single`; other values stop boot. Both modes use the
same tables, policies and organization scope. Organization roots have UUID ids, unique
case-insensitive slugs and an optional onboarding timestamp. PostgreSQL row locks protect
membership changes; there is no persisted `locked_at` flag.

In multi mode, the first authenticated session creates a personal organization when the user
has no memberships. Its owner has full access and its onboarding is incomplete. Explicit
organization creation validates a name, creates an owner membership, records the audit event
and switches the requesting device in one transaction. That organization starts onboarded.

In single mode, boot and `db:seed` idempotently create the shared organization with slug
`default`. The first joining user becomes its owner; subsequent users become members with full
access. Assignment locks the shared organization, so concurrent first sign-ins create exactly
one owner. Organization creation returns `403 forbidden` in this mode.

## Scope and device preferences

`Session.scope_for` returns the user, session, organization and membership. It picks the
session's organization when membership still exists, then the user's last organization, then
the first membership ordered by organization creation time and id. A user with no memberships
receives a personal organization or joins the shared one. The selected organization is saved
on the session, including after a membership is removed.

`PUT /api/v1/current-organization` changes that device's current organization and remembers
the choice in `users.last_organization_id` for new devices. Missing membership returns
`409 not_member`. Existing sessions retain their own choice. Leaving resets the requesting
device immediately; other devices fall back on their next request.

Authenticated bootstrap always contains real `Organization`, `Membership` and `Organization[]`
values. The current membership has `user: null`; member lists and mutation responses include
the serialized user. Anonymous bootstrap has `auth: null`.

## Roles and access

| Role / access | Read organization and members | Manage name, members and invitations |
|---|---|---|
| owner / full | Yes | Yes; can change or create owners |
| admin / full | Yes | Yes; cannot change or remove owners |
| member / full | Yes | No |
| any role / viewer | Yes | No |

Every member may leave their own seat. The last owner cannot leave or be removed
(`409 last_owner`) or be demoted (`422 validation_failed`, `role: validation.last_owner`).
An admin trying to promote or change an owner receives `role: validation.owner_only`;
removing an owner returns `403 forbidden`. Owner counts refer to the role, regardless of access.

Mutations lock the organization before reloading the actor's membership, checking policy,
finding the target through the tenant scope and counting owners. Writes and audits share the
transaction. This prevents stale authority and concurrent removal of all owners.

## Tenant query rule

Tenant models include `TenantScoped`, belong to an organization and carry a non-null
`organization_id`. **The only tenant query entry is `Model.for(scope)`**, including creation,
counts and UUID lookups. Never use `Membership.find`, `Invitation.where`, `unscoped`, or a
root's `memberships` / `invitations` association to fetch tenant rows. Policies deny by default.

The organization root is not itself a tenant row. It resolves authorized roots by joining
memberships filtered by the current user, or invitations filtered by an emailed token digest.
Public preview and acceptance treat the token as a narrow capability; acceptance also requires
the signed-in user's email to match. Registration checks open invitations by normalized email.
These root queries never return tenant rows. Trusted cleanup and delivery jobs resolve roots
internally and then use the same `Model.for(scope)` entry as requests.

`test/architecture/tenancy_test.rb` rejects direct tenant queries, implicit class queries,
unscoped association access and `unscoped`. Every tenant model must have a Pundit policy and
a named `"<Model> tenant isolation ..."` request test in
`test/integration/tenant_isolation_test.rb`. It must prove a member of organization A cannot
list, update or delete organization B's rows through the real API. Supplying an organization
id never establishes authority.

## Invitations, onboarding and subscriptions

Invitations store a SHA-256 digest of an opaque 32-byte token and expire after seven days.
Creation refuses owner roles, existing members and duplicate open emails. Expired pending
invitations for that email are removed before insertion. Acceptance locks the organization,
rechecks expiry and single use, preserves an existing membership, marks acceptance and switches
the device atomically. Revocation deletes the row immediately.

Creation refuses unavailable mail before writing. A commit callback enqueues
`InvitationDeliveryJob` on Solid Queue's `default` queue with an encrypted delivery token.
The email uses the inviter's request locale, per-locale sender and branded layout, and links to
`SPA_ORIGIN/invitations/:token`. Invitation emails carry no unsubscribe headers. Delivery
retries unavailable mail or transport errors after one hour, up to five attempts; revoked or
expired invitations are skipped. `MAIL_ALLOWED_RECIPIENTS` applies outside production.
`InvitationCleanupJob` runs daily at 03:15 on `default`, deleting expired rows through each
organization's scope. Schedules live in `config/recurring.yml`.

Full-access managers can read or finish onboarding. An omitted or blank name keeps the current
name. Completion records `organization.onboarded`; `onboarding_completed` is emitted after
commit with `skipped`. Impersonation does not require or permit onboarding.

Email-subscription tokens are signed over the user id and email digest with no expiry. They
become invalid after an email change or user deletion. GET previews without changing anything;
JSON POST returns the subscription resource. The RFC 8058 form POST requires
`List-Unsubscribe=One-Click` and returns an empty 200. Opt-out is idempotent and audits
`user.optional_emails_stopped` once under a user lock. It does not require a bearer.

Audits include `organization.created`, `organization.updated`, `organization.onboarded`,
`membership.updated`, `membership.deleted`, `organization.member_removed`,
`invitation.created`, `invitation.revoked` and `invitation.accepted`.
Creation and invitation analytics use commit callbacks.
