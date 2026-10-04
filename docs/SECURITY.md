# Security

Sentry scrubs exception messages for user-originated errors (`ApiError`,
`ActiveRecord::RecordInvalid`, and `ActionController::ParameterMissing`) to remove PII;
exception messages for other exceptions are retained for diagnosis. See
[PLATFORM.md](PLATFORM.md) for the remaining event scrubbing rules.
