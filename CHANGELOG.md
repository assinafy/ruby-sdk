# Changelog

All notable changes to the `assinafy` Ruby gem are documented here.

## 1.5.1

### Added

- A complete document workflow in the README and an API reference covering all 89 published
  operations, five supported template operations, request bodies, success responses, errors,
  and all 39 published schemas.
- A weekly upstream contract check and packaged-gem installation smoke test.
- Published RBS signatures and Steep verification in CI and release checks.

### Fixed

- Every client and resource request now sends the exact versioned
  `Assinafy-Ruby-SDK/v1.5.1` User-Agent.
- Public and signer-authenticated operations no longer inherit workspace credentials.
- Collection and binary operations now reject malformed successful responses instead of
  silently returning misleading values.
- Document and template uploads validate safe filenames, non-empty PDF content, and document
  upload IDs before later writes.
- The high-level upload/signature workflow validates every signer before uploading and retains
  created resource IDs in error context for explicit cleanup.
- Request validation now rejects malformed signer fields, assignment items, tag IDs, field
  values, and signer-document identifiers before network calls.

### Changed

- Development and release verification use Ruby 4.0.6 while CI retains Ruby 3.2 compatibility
  and tests Ruby 3.3, 3.4, 4.0, and head.

## 1.5.0

### Added

- **`Resources::AccountResource`** (`client.accounts`): `list`, `create`, `get`, `update`,
  `delete` (with `force:`), `theme`, `stats`, and brand-logo `upload_logo`/`download_logo`/`delete_logo`.
- **`Resources::UserResource`** (`client.users`): `me`, `stats`, and notification-preference
  `GET`/`PUT` wrappers.
- `DocumentResource#search` (`GET /accounts/{account_id}/documents/search`) and
  `#rename` (`PATCH /documents/{document_id}`).
- `AssignmentResource#list` (`GET /assignments`; the account context is sent as the
  camelCase `accountId` query parameter, verified live).
- `SignerDocumentResource#search` (`GET /signers/{signer_id}/documents/search`).
- `AuthResource#link_social_login` (`POST /auth/link-social-login`).
- `SignerResource#upload_signature` accepts an optional `reuse:` flag.
- An opt-in live integration suite (`spec/integration/`, gated by `ASSINAFY_LIVE=1`)
  that drives representative workflows against the sandbox and self-cleans.
- A `.github/dependabot.yml` (bundler + github-actions) so dependency advisories are
  caught automatically.

### Fixed

- `SignerResource#accept_terms` and `#verify_email` now send `signer-access-code` as
  the documented query parameter (the `signerAccessCode` security scheme is `in: query`),
  consistent with every other signer-authenticated endpoint. Previously it was sent
  only in the request body.
- `TemplateResource#create` now performs the required `multipart/form-data` file
  upload. The previous JSON body was rejected by the API (HTTP 400) and never worked.
  Its signature is now `create(source, options = {}, account_id_override = nil)`.
- `SignerDocumentResource#download` makes `signer_access_code:` optional — the endpoint
  is public (`security: []`), so only the document/artifact IDs are required.
- Document search wrappers send the documented `search` query key; downloads accept the
  documented `pades` artifact; signer updates preserve `government_id`.
- `faraday` dependency floor raised to `>= 2.14.3` (CVE-2026-54297, DoS via deeply
  nested query params).

### Removed

- `WebhookResource#delete`. There is no `DELETE /webhooks/subscriptions` route — it
  returns HTTP 404 (verified live). Use `#inactivate` to stop deliveries.

### Documentation

- Corrected YARD payloads verified against live responses: `confirm_data` (body is
  `full_name`/`email`/`government_id`; returns the signer object), `upload_signature`
  (handles documented no-data responses), `FieldResource#update` (accepts only `name`/`regex`/`is_active`),
  webhook dispatch shape (ISO-8601 `created_at` + `updated_at`), and template `create`.
- README updated for the new resources and behaviors, plus live-test instructions.

## 1.4.0

This release aligned the SDK with the live Assinafy v1 API and the published
documentation at <https://api.assinafy.com.br/v1/docs>.

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
  4.0, and head. `.ruby-version` is committed (3.4.8) and drives the lint, security, and release jobs.
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
