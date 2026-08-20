# Assinafy Ruby SDK — Full API Audit (v1.4.0 → v1.5.0)

**Date:** 2026-07-20 (refreshed 2026-08-20)
**Auditor:** SDK maintenance pass
**API version:** Assinafy v1
**Source of truth:** `https://api.assinafy.com.br/v1/docs/openapi.json` (OpenAPI 3.0.0 — 67 paths / **89 operations** / 39 schemas)
**Verified against:** live sandbox `https://sandbox.assinafy.com.br/v1`

## 1. Method

1. **Reconciled** the SDK against the OpenAPI spec, operation by operation (89 ops), including
   parameters, request-body schemas, and response schemas.
2. **Live-verified** safe representative workflows against the sandbox, capturing real
   request/response payloads where credentials and feature rollout allowed.
3. **Fixed** correctness gaps, **added** missing endpoints, and **corrected** documentation to match
   observed behavior.
4. **Locked in** the results with mocked specs (fast, hermetic) *and* an opt-in live integration
   suite (real sandbox, `ASSINAFY_LIVE=1`).

> **Source-of-truth change since v1.4.0:** the docs migrated from a single Slate HTML page to a
> **Scalar** reference backed by a machine-readable **OpenAPI** document. `/v1/docs` is now a JS
> shell; the audit consumed `/v1/docs/openapi.json` directly.

## 2. Coverage summary

| | Count |
|---|---|
| OpenAPI operations | 89 |
| Wrapped by the SDK | 89 |
| Additional sandbox-live template routes | 5 |
| SDK methods live-verified against the sandbox | representative safe workflows (see §6) |

Coverage is enforced in CI by `spec/api_coverage_spec.rb`.

## 3. Endpoints added

All live-confirmed on the sandbox unless flagged.

| Resource | Methods |
|---|---|
| **`AccountResource`** (`client.accounts`) | `list`, `create`, `get`, `update`, `delete(force:)`, `theme`, `stats`⚠, `upload_logo`, `download_logo`, `delete_logo` |
| **`UserResource`** (`client.users`) | `me`, `stats`⚠, `notification_preferences`⚠, `update_notification_preferences`⚠ |
| `DocumentResource` | `search`, `rename` (`PATCH /documents/{id}`) |
| `AssignmentResource` | `list` (`GET /assignments?accountId=…`) |
| `SignerDocumentResource` | `search` |
| `AuthResource` | `link_social_login` |

⚠ The stats and notification-preference routes are defined in the spec but return **404 on the
sandbox**. They are implemented per the spec and clearly flagged as unavailable in this environment.

## 4. Correctness fixes (with evidence)

| Fix | Evidence |
|---|---|
| `SignerResource#accept_terms` / `#verify_email` — send `signer-access-code` as a **query** param | `signerAccessCode` security scheme is `in: query`; every other signer endpoint already used the query. Body-only would not authenticate. |
| `TemplateResource#create` — **multipart file upload** (was JSON) | Live: JSON body → `400 "The Content-Type header must be multipart/form-data"`. Multipart PDF → `200` with an auto-created `TemplateEditor` role. |
| `SignerDocumentResource#download` — `signer_access_code:` now optional | Live: the endpoint returned `200` (raw PDF) with no access code — it is public (`security: []`). |
| `WebhookResource#delete` — **removed** | Live: `DELETE /accounts/{id}/webhooks/subscriptions` → `404 "Página não encontrada"`. Use `#inactivate`. |
| `faraday` floor → `>= 2.14.3` | CVE-2026-54297 (uncontrolled recursion / DoS via nested query params). |

## 5. Spec-vs-reality discrepancies (SDK follows reality)

Verifying live prevented several "fixes" that would have broken correct code:

- **`documents.send_token`** — the spec permits no body or `{email}`, but the live API requires
  `{recipient, channel}` when supplying a recipient (a bare `{email}` → `400 "channel obrigatório"`).
  The SDK supports all three forms.
- **`documents.public_info`** — the spec implies the full Document schema, but the endpoint returns
  a minimal `{resource, id, name, page_count, created_by}`. The SDK is correct.
- **`GET /assignments`** — requires the account context as the **camelCase** `accountId` query
  param (`account_id` → `400`). Only camelCase query param in the API.
- **Template routes** (`get`/`create`/`update`/`delete`/`download_page`) are **real and live-verified**
  but are **not present in the OpenAPI document**. Kept and documented as such.
- **`GET /auth/authenticate`** is absent from the current OpenAPI and returned **404** on both
  production and sandbox. Its unreleased URL-builder wrapper was removed before v1.5.0.
- **Signer-document reads** work with workspace API-key authentication and additional filters on
  the sandbox; the OpenAPI declares signer-access-code authentication and narrower query sets.
- **Field validation** is described as part of signer flows but its OpenAPI security block lists
  only bearer/API-key authentication. The SDK supports both documented workspace auth and the
  signer-code query used by deployed signing flows.
- **Resend-cost responses** use `has_sufficient_resources` in the OpenAPI and
  `has_sufficient_credits` on the current sandbox; the SDK passes either response through.
- **Document tag attachment** uses tag IDs in the OpenAPI, while the sandbox also accepts existing
  tag names. The SDK passes either string form through and documents IDs as the portable default.
- **Document upload/assignment extensions:** the sandbox accepts multipart `name`, and accepts
  `expires_at: null` to clear expiration. Those live-compatible forms are retained and documented
  even where the current request schemas are narrower.

## 6. Not fully verifiable with a workspace API key

The signer-side write endpoints authenticate with an **emailed OTP** access code, not the account
key (an assignment's `signing_urls` contain only `…/sign/{doc}?email=…`, no code). These are
covered by mocked specs and documented from the spec, but cannot be driven end-to-end here:
`assignments.sign`, `signers.self_data`/`accept_terms`/`verify_email`/`confirm_data`,
`signers.upload_signature`/`download_signature`, `signer_documents.current`/`sign_multiple`/`decline_multiple`.
Password/reset/social-login operations require credentials or provider tokens that were not supplied.
API-key creation/deletion was not used because it can rotate or revoke the only supplied sandbox key;
the read-only API-key endpoint was verified live. The stats and notification-preference endpoints (§3)
return 404 on the sandbox. All of these wire contracts have exact mocked request/response coverage.

## 7. Security & tooling

- **bundler-audit: clean with no suppression file.** `faraday` remains at the remediated floor,
  and the fresh dependency resolution uses `json` 2.21.2.
- **Dependabot** added (`bundler` + `github-actions`, weekly) so future advisories surface as PRs.
- **CI** (already strong): matrix `[3.2, 3.3, 3.4, 4.0, head]`, least-privilege `permissions`,
  `concurrency`, `timeout-minutes`, `bundler-cache`; separate rspec / rubocop / bundler-audit jobs.
- **Release** verifies the tag, re-runs the full gate, builds once, and publishes the same gem to
  RubyGems via OIDC and GitHub Packages. The protected `release` environment and pending
  RubyGems trusted publisher must be configured before tagging.

## 8. Verification results

- **Default suite:** `248 examples, 0 failures` (RSpec + WebMock), including the coverage matrix
  and offline live-test safety guards.
- **Live API suite:** `12 examples, 0 failures, 1 pending` against the sandbox; notification
  preferences are pending because that documented route returns 404 there. Cleanup is independent.
- **RuboCop:** clean (40 files). **bundler-audit:** no vulnerabilities. Gem build/install/require: clean.
- **Ruby:** gem floor `>= 3.2`; 248 examples pass on 3.2.11, 3.3.12, 3.4.10, and 4.0.6;
  CI also covers `head`. The tooling runtime is 4.0.6.

## 9. Version

`1.5.0` adds the current API surface and correctness fixes. It also removes `webhooks.delete`,
whose route returned 404, and changes `templates.create`, whose previous JSON request returned
400. Both behaviors were tested against the sandbox before changing them. See `CHANGELOG.md`.
