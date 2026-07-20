# Assinafy Ruby SDK — Full API Audit (v1.4.0 → v1.5.0)

**Date:** 2026-07-20
**Auditor:** SDK maintenance pass
**API version:** Assinafy v1
**Source of truth:** `https://api.assinafy.com.br/v1/docs/openapi.json` (OpenAPI 3.0.0 — 68 paths / **89 operations** / 37 schemas)
**Verified against:** live sandbox `https://sandbox.assinafy.com.br/v1`

## 1. Method

1. **Reconciled** the SDK against the OpenAPI spec, operation by operation (89 ops), including
   parameters, request-body schemas, and response schemas.
2. **Live-verified** every reachable endpoint against the sandbox, capturing real request/response
   payloads (the evidence backs the YARD examples and the fixtures).
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
| Wrapped by the SDK | 88 |
| Intentionally not wrapped | 1 — `GET /login-callback` (browser OAuth redirect, no SDK use) |
| SDK methods live-verified against the sandbox | all reachable endpoints (see §6 for the OTP-gated exceptions) |

Coverage is enforced in CI by `spec/api_coverage_spec.rb`.

## 3. Endpoints added

All live-confirmed on the sandbox unless flagged.

| Resource | Methods |
|---|---|
| **`AccountResource`** (`client.accounts`) | `list`, `create`, `get`, `update`, `delete(force:)`, `theme`, `stats`⚠, `upload_logo`, `download_logo`, `delete_logo` |
| **`UserResource`** (`client.users`) | `me` (`GET /users/self`), `stats`⚠ |
| `DocumentResource` | `search`, `rename` (`PATCH /documents/{id}`) |
| `AssignmentResource` | `list` (`GET /assignments?accountId=…`) |
| `SignerDocumentResource` | `search` |
| `AuthResource` | `link_social_login`, `social_login_url` (URL builder) |

⚠ `accounts/{id}/stats` and `users/self/stats` are defined in the spec but return **404 on the
sandbox**. They are implemented per the spec and clearly flagged as not verifiable in this environment.

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

- **`documents.send_token`** — the spec shows a `{email}` body, but the live API requires
  `{recipient, channel}` (a bare `{email}` → `400 "channel obrigatório"`). The SDK is correct.
- **`documents.public_info`** — the spec implies the full Document schema, but the endpoint returns
  a minimal `{resource, id, name, page_count, created_by}`. The SDK is correct.
- **`GET /assignments`** — requires the account context as the **camelCase** `accountId` query
  param (`account_id` → `400`). Only camelCase query param in the API.
- **Template routes** (`get`/`create`/`update`/`delete`/`download_page`) are **real and live-verified**
  but are **not present in the OpenAPI document**. Kept and documented as such.

## 6. Not fully verifiable with a workspace API key

The signer-side write endpoints authenticate with an **emailed OTP** access code, not the account
key (an assignment's `signing_urls` contain only `…/sign/{doc}?email=…`, no code). These are
covered by mocked specs and documented from the spec, but cannot be driven end-to-end here:
`assignments.sign`, `signers.self_data`/`accept_terms`/`verify_email`/`confirm_data`,
`signers.upload_signature`/`download_signature`, `signer_documents.current`/`sign_multiple`/`decline_multiple`.
The two `stats` endpoints (§3) return 404 on the sandbox.

## 7. Security & tooling

- **bundler-audit: clean.** `faraday` bumped (CVE-2026-54297). One low-severity transitive `json`
  advisory (CVE-2026-54696) is documented and ignored in `.bundler-audit.yml`: Ruby 4.0 ships
  json 2.19.5 and the patched line does not yet compile against Ruby 4.0 headers; the SDK never
  uses the vulnerable `JSON.generate`-to-IO path. Resolves automatically on Ruby 3.2–3.4.
- **Dependabot** added (`bundler` + `github-actions`, weekly) so future advisories surface as PRs.
- **CI** (already strong): matrix `[3.2, 3.3, 3.4, 4.0, head]`, least-privilege `permissions`,
  `concurrency`, `timeout-minutes`, `bundler-cache`; separate rspec / rubocop / bundler-audit jobs.
- **Release** workflow verifies the tag matches `Assinafy::VERSION`, re-runs the full gate, and
  publishes to GitHub Packages + RubyGems.

## 8. Verification results

- **Mocked suite:** `203 examples, 0 failures` (RSpec + WebMock), including the coverage matrix.
- **Live integration suite:** `10 examples, 0 failures` against the sandbox (users, accounts+logo,
  document+assignment lifecycle with real emails, signers, fields, tags, webhooks+restore,
  templates via multipart, statuses/verify). Each example self-cleans.
- **RuboCop:** clean (40 files). **bundler-audit:** no vulnerabilities.
- **Ruby:** gem floor `>= 3.2`; verified locally on Ruby 4.0.3; CI covers 3.2–4.0 + head.

## 9. Version

`1.5.0` — additive and non-breaking, with one removal (`webhooks.delete`, a route that never
existed) and one signature change (`templates.create`, a method that never worked). See
`CHANGELOG.md`.
