# Changelog

All notable changes to the `assinafy` Ruby gem are documented here.

## 1.4.0

This release is the result of a full audit of the SDK against the live Assinafy
v1 API (verified end-to-end against the sandbox) and the published documentation
at <https://api.assinafy.com.br/v1/docs>.

### Added

- `Resources::TemplateResource#delete` (`DELETE /accounts/{account_id}/templates/{template_id}`)
  and `#download_page` (`GET /accounts/{account_id}/templates/{template_id}/pages/{page_id}/download`)
  — both verified against the live API.
- `Support::WebhookVerifier#event_payload`, `#event_object`, and `#event_subject`,
  matching the real delivery envelope (top-level `payload`/`object`/`subject` keys).
- `ApiError#error_name` and `ApiError#error_code` expose the API's `name`/`code`
  error fields; `ApiError.from_response` now also falls back to `name` for the message.
- YARD `@example` blocks with full request **and** response payloads on every public
  method, sourced from the live API and the docs.
- Behavioral coverage: `spec/api_coverage_spec.rb` now also fails CI when a public
  endpoint wrapper is missing a matrix row, and asserts documented aliases still
  resolve to their canonical methods. Behavioral WebMock specs were added for the
  previously untested methods and for `Client#upload_and_request_signatures`.

### Fixed

- `AssignmentResource#reset_expiration` now sends `expires_at` verbatim, so an
  explicit `nil` is serialized as JSON `null` ("no expiration") instead of being
  dropped from the body (the field is required by the API). Verified live.
- `Support::WebhookVerifier#event_data`/`#event_type` corrected to the real envelope:
  `event_type` reads `event` (the fabricated `type` fallback was removed), and
  `event_data` is deprecated in favor of `#event_payload`/`#event_object`.
- `DocumentResource#send_token` validates `recipient`/`channel` before the request.
- `SignerResource#find_by_email` now paginates through all result pages instead of
  relying on a single oversized page (the API clamps `per-page` to its own maximum —
  observed as 50 on the sandbox).
- `Client#upload_and_request_signatures` raises a clear `ApiError` if a created
  signer comes back without an ID, rather than building an assignment with `nil` IDs.
- `TagResource#update` rejects an empty payload or a blank name before issuing a no-op PUT.

### Changed

- **Minimum Ruby is now 3.2** (3.0 and 3.1 are end-of-life). CI tests 3.2, 3.3, 3.4,
  4.0, and head. `.ruby-version` is committed (3.4.8) and drives the lint/audit/release jobs.
- `SignerDocumentResource#list` accepts an optional `signer_access_code:` (the endpoint
  also supports workspace `X-Api-Key` auth); the class auth documentation was corrected.
- CI gained a `concurrency` group to cancel superseded runs.

## 1.3.1

### Added

- `Client#tags` and `Resources::TagResource` for the documented workspace tag
  endpoints.
- Document tag helpers on `Resources::DocumentResource`: `list_tags`,
  `replace_tags`, `append_tags`, and `detach_tag`.

### Fixed

- Assignment signer payloads now preserve the documented `step` field for
  sequential signing.

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
