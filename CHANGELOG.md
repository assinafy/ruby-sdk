# Changelog

All notable changes to the `assinafy` Ruby gem are documented here.

## 1.3.0

### Added

- YARD documentation for every public method on `Client`, `Configuration`,
  every `Resources::*` class, `Support::WebhookVerifier`, and the SDK's
  error hierarchy.
- `spec/api_coverage_spec.rb` — an explicit, version-controlled matrix that
  asserts every documented endpoint at
  https://api.assinafy.com.br/v1/docs has a corresponding SDK method.

### Fixed

- `AssignmentResource#sign` now translates snake_case keys (`item_id`,
  `field_id`, `page_id`, `value`) to the camelCase keys (`itemId`, `fieldId`,
  `pageId`, `value`) that the `POST /documents/{documentId}/assignments/{assignmentId}`
  endpoint expects — the only place the API deviates from snake_case.
  Already-camelCase input is passed through unchanged.

### Changed

- README expanded with one runnable example per resource matching the
  documented Assinafy v1 surface area.

## 1.2.0

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

### Release

- Added a tag-triggered release workflow that publishes to both GitHub
  Packages (`rubygems.pkg.github.com/assinafy`) and RubyGems.org. The verify
  job blocks publishing when the git tag does not match `Assinafy::VERSION`.
