# Changelog

All notable changes to the `assinafy` Ruby gem are documented here.

## Unreleased

### Changed

- Consolidated HTTP error handling in `BaseResource` behind a single private
  `request` helper used by `call`, `call_void`, `call_binary`, `call_list`,
  and `call_optional`.
- Pagination metadata extraction in `BaseResource` is now driven by a
  declarative header → key mapping.
- `Client.from_config` now delegates to `Configuration.from_hash`. A new
  `Client.from_hash` alias is exposed for symmetry with `Configuration`.
- `Client#upload_and_request_signatures` no longer duplicates the signer
  payload normalization logic — it relies on `SignerResource#create`.
- `NullLogger` now responds to the full Ruby `Logger` severity surface.
- Minimum Ruby is now 3.0 (matching the CI matrix).

### Removed

- Undocumented `expiration` field from `AssignmentResource.build_payload`
  — only `expires_at` is documented in the public API.

### Fixed

- Documented `signer-access-code` and pagination handling are now consistent
  across every resource.
