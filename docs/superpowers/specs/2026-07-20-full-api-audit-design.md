# Full API Audit — Assinafy Ruby SDK (v1.4.0 → v1.5.0)

Status: **Historical design snapshot** (approved 2026-07-20; superseded by the implemented audit report)
Source of truth: `https://api.assinafy.com.br/v1/docs/openapi.json` (OpenAPI 3.0.0, 68 paths / 89 operations / 37 schemas)
Sandbox: `https://sandbox.assinafy.com.br/v1` (live-tested with the provided sandbox key)

## Goal

Bring the SDK to 100% alignment with the current OpenAPI spec, live-verified against the
sandbox, fully documented with real request/response payloads, and production-ready on a
modern Ruby/CI baseline.

**Guardrail:** Behavior-preserving. Nothing is removed without a failing live test proving it
is dead, and any such removal is surfaced to the maintainer before it happens.

## Decisions (locked)

1. **Live testing:** Full end-to-end against sandbox — signature-request emails to explicitly
   configured test recipients, with deletes for cleanup.
2. **Ruby target:** keep gemspec floor `>= 3.2`; CI matrix `[3.2, 3.3, 3.4, 4.0]`; fix
   `.ruby-version` drift.
3. **Deliverable:** opt-in live integration suite (`ASSINAFY_LIVE=1`) + captured fixtures +
   written audit report; CI default stays fast + mocked.
4. **Refactor scope:** correctness + coverage + docs; refactor only clear DRY wins,
   behavior-preserving.
5. **New resources:** `client.accounts` (AccountResource) and `client.users` (UserResource).
6. **Spec-documented-but-sandbox-404 endpoints** implemented per spec + flagged as unverifiable.
7. **Version → 1.5.0** (additive, non-breaking).

## Gap analysis (spec 89 ops vs SDK)

### New endpoints to add (live-confirmed real unless flagged)

| Resource | Methods |
|---|---|
| `AccountResource` (new) | `list` GET /accounts, `create` POST /accounts, `get` GET /accounts/{id}, `update` PUT /accounts/{id}, `delete` DELETE /accounts/{id}, `theme` GET .../theme, `download_logo` GET .../logo, `upload_logo` POST .../logo, `delete_logo` DELETE .../logo, `stats` GET .../stats ⚠404 |
| `UserResource` (new) | `me` GET /users/self, `stats` GET /users/self/stats ⚠404 |
| `DocumentResource` | `search` GET /accounts/{id}/documents/search, `rename` PATCH /documents/{id} |
| `AssignmentResource` | `list` GET /assignments (needs account context) |
| `SignerDocumentResource` | `search` GET /signers/{id}/documents/search |
| `AuthResource` | `link_social_login` POST /auth/link-social-login, `social_login_url` GET /auth/authenticate |

⚠404 = documented in spec but returns 404 on sandbox → implement per spec, mark unverifiable.

### SDK methods absent from the spec (verify live; keep or flag)

- `TemplateResource#get/create/update/delete/download_page`
- `WebhookResource#delete` (DELETE /accounts/{id}/webhooks/subscriptions)

Live-probe each; keep whatever responds correctly. Anything that 404s is flagged in the report
and removal is confirmed with the maintainer before acting.

### Not wrapped (out of scope — browser-only OAuth redirects)

- `GET /login-callback`, `GET /auth/authenticate` is a redirect starter (wrapped as a URL builder only).

## Correctness pass

Reconcile all ~75 existing methods against spec parameters, request-body schemas, and response
schemas; live-verify each (path/verb, param names, `sign` camelCase body, required-field
validation, `{status,message,data}` envelope unwrap, pagination headers, binary downloads). Fix
mismatches in place.

## Live verification strategy

Full E2E run: upload PDF → create signers → request signatures (real emails) → inspect
assignment/signing URLs → exercise tags/fields/webhooks/accounts → clean up with deletes.
Captured real payloads feed (a) the audit report, (b) fixtures backing mocked specs, (c) the
opt-in integration suite (`spec/integration/`, gated by `ASSINAFY_LIVE=1` + env creds).

## Documentation

Every public method: YARD with a full real request body + full real response payload (captured
live, secrets redacted). README endpoint table + examples; CHANGELOG; coverage matrix +
`MEMORY.md` quirks updated.

## Tooling / CI

Fix `.ruby-version`; gemspec floor `>= 3.2`; CI matrix `[3.2, 3.3, 3.4, 4.0]`. Harden workflows:
SHA-pinned actions, least-privilege `permissions:`, `concurrency:`, `bundler-cache`, run
rspec + rubocop + bundler-audit. Review the release workflow (GitHub Packages + RubyGems) given
the GitLab→GitHub mirror.

## Deliverables

New resources/methods + fixes; full YARD; opt-in live suite + fixtures; audit report
(`docs/audit/…`); updated README/CHANGELOG/coverage-matrix; version → 1.5.0. All 180 existing
specs stay green plus new coverage. rubocop + bundler-audit clean.
