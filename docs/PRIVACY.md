# Account deletion

`GET /api/v1/settings/account` previews deletion as `AccountDeletion { blocker }`.
`DELETE /api/v1/settings/account` deletes the signed-in account and returns an empty 204.
Both actions require a live, non-impersonating session with sudo. DELETE permits five attempts
per minute per client IP and returns the standard 429 envelope and retry header above the limit.

The preview checks every organization the user belongs to, in organization creation order.
The first blocker is null or `{ reason, organization }`, with the organization name:

- `transfer_ownership`: the user is the only owner and another member remains. Promote another
  member to owner first. Owner counts include both full and viewer access.
- `subscription_active`: the user is the only member and any subscription in either test or
  live mode has a status other than `canceled` or `incomplete_expired`. Cancel it first. Billing
  being disabled does not remove this blocker; paused, unpaid and incomplete statuses can still
  charge and remain blocked.

DELETE locks the user's organization roots in id order, then locks the user and reads the
memberships again. Membership mutations and invitation acceptance use the same organization
locks. The preview is advisory: the mutation rechecks current blockers after waiting, returning
409 with `details.organization` and writing no deletion or audit data when blocked.

A successful transaction removes the user, memberships, all sessions and emailed tokens.
Foreign keys nullify inviter and impersonation references. It deletes organizations left empty
when they have no subscription records, including their invitations through database cascades.
An empty organization with closed subscription history remains with its billing records.
`Subscription.for(scope)` enforces tenant isolation, and deletion checks both billing modes.
The subscription table currently provides the status and mode required for deletion; payment
provider reconciliation belongs to billing.

Legal acceptance records retain the accepted timestamp, IP, version map and email hash, with
`user_id = null`. Registration writes this record alongside the user's consent fields; existing
consent fields are backfilled by migration. No unpublished version is invented.

Append-only audits retain `user.deleted` (actor and subject are the deleted user's id), and
`organization.deleted` for each removed empty organization. They contain no password or token.
Every account bearer becomes invalid after deletion; the SPA clears its stored token.
