# Assinafy Ruby SDK API Reference

> Contract source: Assinafy API v1 OpenAPI 3.1.0, retrieved 2026-11-11 from
> `https://api.assinafy.com.br/v1/docs/openapi.json` (112 paths, 147 operations, 62 schemas).
> `scripts/check_api_contract.rb` validates contract compatibility weekly.

This is the SDK-facing contract reference. Paths below are wire paths; Ruby methods return the unwrapped
`data` member for Assinafy response envelopes, pagination helpers return `{ data:, meta: }`, binary methods
return bytes, and documented no-data operations return `nil`.

Required parameters and object properties are marked with `*`.

## Authentication and safety

- `X-Api-Key` is the recommended server-side credential. A bearer token is either a login session token or an
  OAuth 2.1 access token. If both an API key and a token are configured, the current SDK sends only `X-Api-Key`;
  prefer configuring exactly one credential.
- OAuth 2.1 authenticates an application acting *in a user's workspace with that user's permission*, as opposed
  to `X-Api-Key`/bearer, which authenticate the workspace or user directly. The flow is authorization-code with
  mandatory PKCE `S256`; `Assinafy::OAuth` builds the verifier, challenge, `state`, and authorization URL, and
  `client.oauth` covers the token lifecycle. A token is scoped to one workspace and carries only the scopes the
  user approved, and it never reaches billing, account lifecycle, credential management, or admin surfaces
  regardless of scope. A missing scope answers `403` with a `WWW-Authenticate` challenge naming it, which the
  SDK exposes as `ApiError#context[:www_authenticate]` on every resource: reconnect with that scope added rather
  than retrying. Store the `code_verifier`, `state`, and expected issuer with each authorization attempt — the
  issuer of the authorization server it uses: `https://auth.assinafy.com.br` in production,
  `https://auth-sandbox.assinafy.com.br` in the sandbox. Check `state` and `iss` against those stored values on
  the callback before anything else, including an `error=` return, and keep refresh tokens out of logs.
- Signer-facing operations use the one-time `signer-access-code` query parameter where shown. Never log, commit,
  or place API keys, bearer tokens, signer codes, or real recipient addresses in examples or fixtures.
- `POST /v1/login` answers with an `mfa_token` challenge instead of an access token when the user has two-factor
  authentication enabled. `AuthResource#verify_mfa` exchanges it, without workspace credentials; the challenge is
  single-use and expires 5 minutes after login.
- Webhook endpoint signing secrets (`whsec_...`) are readable only with an API key or user session.
  OAuth applications with `webhooks:write` can rotate secrets and must store the returned value. Treat them like API keys. Verify every delivery with
  `WebhookVerifier#verify_delivery` against the raw request body.
- HTTP connections require TLS 1.2 or newer and use Ruby/Faraday TLS verification and the host system trust store;
  the SDK does not pin the upstream TLS certificate.
- `DocumentResource#verify` reports Assinafy upstream verification data. It does not independently validate a PDF
  signature, certificate chain, OCSP/CRL status, or legal validity. The API artifact name `certificated` is not an
  additional local guarantee.

## API operations

| Method | Path | Ruby SDK method | Authentication | Parameters | Request body | Success wire response |
| --- | --- | --- | --- | --- | --- | --- |
| GET | `/v1/accounts/{accountId}` | `AccountResource#get` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `expand`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Account`](#account) } |
| PUT | `/v1/accounts/{accountId}` | `AccountResource#update` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `application/json` object { `name`: string; `notification_sender_type`: string (`"User"`, `"Account"`) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Account`](#account) } |
| DELETE | `/v1/accounts/{accountId}` | `AccountResource#delete` | Bearer token or `X-Api-Key` | path `accountId*`: string | optional; `application/json` object { `force`: boolean } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| GET | `/v1/accounts/{accountId}/theme` | `AccountResource#theme` | Bearer token or `X-Api-Key` | path `accountId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`AccountTheme`](#accounttheme) } |
| GET | `/v1/accounts/{accountId}/usage` | `AccountResource#usage` | Bearer token or `X-Api-Key` | path `accountId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`AccountUsage`](#accountusage) } |
| GET | `/v1/accounts/{accountId}/logo` | `AccountResource#download_logo` | Bearer token or `X-Api-Key` | path `accountId*`: string | None | `200` `image/*` string (format: binary) |
| POST | `/v1/accounts/{accountId}/logo` | `AccountResource#upload_logo` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `multipart/form-data` object { `file*`: string (format: binary) } | `200` `application/json` [`Envelope`](#envelope) |
| DELETE | `/v1/accounts/{accountId}/logo` | `AccountResource#delete_logo` | Bearer token or `X-Api-Key` | path `accountId*`: string | None | `200` `application/json` [`Envelope`](#envelope) |
| GET | `/v1/accounts` | `AccountResource#list` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Account`](#account)> } |
| POST | `/v1/accounts` | `AccountResource#create` | Bearer token or `X-Api-Key` | None | required; `application/json` object { `name*`: string; `notification_sender_type`: string (`"User"`, `"Account"`) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Account`](#account) } |
| GET | `/v1/documents/{documentId}/activities` | `DocumentResource#activities` | Bearer token or `X-Api-Key` | path `documentId*`: string<br>query `sort`: string<br>query `page`: integer (min: 1)<br>query `per-page`: integer (min: 1) (max: 50) | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`DocumentActivity`](#documentactivity)> } |
| GET | `/v1/assignments` | `AssignmentResource#list` | Bearer token or `X-Api-Key` | query `accountId`: string<br>query `sort`: string<br>query `page`: integer (min: 1)<br>query `per-page`: integer (min: 1) (max: 50) | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Assignment`](#assignment)> } |
| POST | `/v1/documents/{documentId}/assignments` | `AssignmentResource#create` | Bearer token or `X-Api-Key` | path `documentId*`: string | required; `application/json` object { `method*`: string (`"virtual"`, `"collect"`); `signers*`: Array<object { `id*`: string; `verification_method`: string (`"Email"`, `"Whatsapp"`, `"DigitalCertificate"`, `"IdDocumentFaceMatchBasic"`); `notification_methods`: Array<string (`"Email"`, `"Whatsapp"`)>; `embedded`: boolean; `step`: integer }>; `entries`: Array<object { `page_id`: string; `fields`: Array<object { `signer_id`: string; `field_id`: string; `display_settings`: [`DisplaySettings`](#displaysettings) }> }>; `message`: string; `expires_at`: string (format: date-time); `copy_receivers`: Array<string>; `max_total_credits`: number } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Assignment`](#assignment) } |
| POST | `/v1/documents/{documentId}/assignments/estimate-cost` | `AssignmentResource#estimate_cost` | Bearer token or `X-Api-Key` | path `documentId*`: string | required; `application/json` object { `method`: string (`"virtual"`, `"collect"`); `signers`: Array<object { `verification_method`: string (`"Email"`, `"Whatsapp"`, `"DigitalCertificate"`, `"IdDocumentFaceMatchBasic"`); `notification_methods`: Array<string (`"Email"`, `"Whatsapp"`)> }>; `entries`: Array<object> } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`CostEstimate`](#costestimate) } |
| PUT | `/v1/documents/{documentId}/assignments/{assignmentId}/signers/{signerId}/resend` | `AssignmentResource#resend_notification` | Bearer token or `X-Api-Key` | path `documentId*`: string<br>path `assignmentId*`: string<br>path `signerId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `is_sent`: boolean; `document_id`: string; `signer_id`: string } } |
| POST | `/v1/documents/{documentId}/assignments/{assignmentId}/signers/{signerId}/estimate-resend-cost` | `AssignmentResource#estimate_resend_cost` | Bearer token or `X-Api-Key` | path `documentId*`: string<br>path `assignmentId*`: string<br>path `signerId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`ResendCostEstimate`](#resendcostestimate) } |
| PUT | `/v1/documents/{documentId}/assignments/{assignmentId}/reset-expiration` | `AssignmentResource#reset_expiration` | Bearer token or `X-Api-Key` | path `documentId*`: string<br>path `assignmentId*`: string | required; `application/json` object { `expires_at*`: string or null (format: date-time) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Assignment`](#assignment) } |
| GET | `/v1/documents/{documentId}/assignments/{assignmentId}/signers/{signerId}/identity-verification` | `AssignmentResource#identity_review` | Bearer token or `X-Api-Key` | path `documentId*`: string<br>path `assignmentId*`: string<br>path `signerId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`SignerIdentityReview`](#signeridentityreview) } |
| GET | `/v1/documents/{documentId}/assignments/{assignmentId}/signers/{signerId}/identity-verification/images/{name}` | `AssignmentResource#identity_review_image` | Bearer token or `X-Api-Key` | path `documentId*`: string<br>path `assignmentId*`: string<br>path `signerId*`: string<br>path `name*`: string (`"document_front"`, `"document_back"`, `"document_pdf"`, `"face"`) | None | `200` `image/jpeg` string (format: binary)<br>`image/png` string (format: binary)<br>`application/pdf` string (format: binary) |
| POST | `/v1/documents/{documentId}/assignments/{assignmentId}/signers/{signerId}/identity-verification/review` | `AssignmentResource#decide_identity_review` | Bearer token or `X-Api-Key` | path `documentId*`: string<br>path `assignmentId*`: string<br>path `signerId*`: string | required; `application/json` object { `decision*`: string (`"Approved"`, `"Rejected"`); `note`: string or null (max length: 2000) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`SignerIdentityReview`](#signeridentityreview) } |
| POST | `/v1/login` | `AuthResource#login` | Public | None | required; `application/json` object { `email*`: string (format: email); `password*`: string (format: password) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`AuthSession`](#authsession) } |
| PUT | `/v1/authentication/request-password-reset` | `AuthResource#request_password_reset` | Public | None | required; `application/json` object { `email*`: string (format: email) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `email`: string (format: email) } } |
| PUT | `/v1/authentication/reset-password` | `AuthResource#reset_password` | Public | None | required; `application/json` object { `email*`: string (format: email); `token`: string; `new_password*`: string (format: password) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `email`: string (format: email) } } |
| PUT | `/v1/authentication/change-password` | `AuthResource#change_password` | Bearer token or `X-Api-Key` | None | required; `application/json` object { `email*`: string (format: email); `password*`: string (format: password); `new_password*`: string (format: password) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `email`: string (format: email) } } |
| POST | `/v1/authentication/mfa/verify` | `AuthResource#verify_mfa` | Public | None | required; `application/json` object { `mfa_token*`: string; `code*`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`AuthSession`](#authsession) } |
| GET | `/v1/accounts/{accountId}/contracts` | `ContractResource#list` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `status`: Array<string (`"draft"`, `"active"`, `"expired"`, `"terminated"`)><br>query `counterparty`: string<br>query `search`: string<br>query `end_date_from`: string (format: date)<br>query `end_date_to`: string (format: date)<br>query `ending_within_days`: integer (min: 0) (max: 3650)<br>query `external_system`: string<br>query `external_id`: string<br>query `sort`: string<br>query `expand`: string<br>query `page`: integer (min: 1)<br>query `per-page`: integer (min: 1) (max: 50) | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`DocumentContract`](#documentcontract)> } |
| GET | `/v1/accounts/{accountId}/documents/{documentId}/contract` | `ContractResource#get` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `documentId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`DocumentContract`](#documentcontract) or [`DocumentContractAmendment`](#documentcontractamendment) } |
| PUT | `/v1/accounts/{accountId}/documents/{documentId}/contract` | `ContractResource#update` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `documentId*`: string | required; `application/json` [`DocumentContractInput`](#documentcontractinput) | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`DocumentContract`](#documentcontract) or [`DocumentContractAmendment`](#documentcontractamendment) } |
| GET | `/v1/accounts/{accountId}/documents/{documentId}/contract/related` | `ContractResource#related` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `documentId*`: string<br>query `expand`: string (`"document"`) | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`DocumentContract`](#documentcontract) } |
| POST | `/v1/accounts/{accountId}/documents/{documentId}/contract/renew` | `ContractResource#renew` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `documentId*`: string | optional; `application/json` object { `end_date`: string or null (format: date); `value`: number or null; `term`: integer (min: 1); `updated_at`: string (format: date-time) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`DocumentContract`](#documentcontract) } |
| POST | `/v1/accounts/{accountId}/documents/{documentId}/contract/terminate` | `ContractResource#terminate` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `documentId*`: string | optional; `application/json` object { `reason`: string or null (max length: 500); `updated_at`: string (format: date-time) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`DocumentContract`](#documentcontract) } |
| GET | `/v1/accounts/{accountId}/documents` | `DocumentResource#list` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `status`: string<br>query `envelope_id`: string<br>query `method`: string (`"virtual"`, `"collect"`)<br>query `search`: string<br>query `tags`: string<br>query `sort`: string<br>query `page`: integer (min: 1)<br>query `per-page`: integer (min: 1) (max: 50) | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Document`](#document)> } |
| POST | `/v1/accounts/{accountId}/documents` | `DocumentResource#upload` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `multipart/form-data` object { `file*`: string (format: binary) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Document`](#document) } |
| GET | `/v1/accounts/{accountId}/documents/search` | `DocumentResource#search` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `search`: string<br>query `status`: string<br>query `envelope_id`: string<br>query `sort`: string<br>query `page`: integer (min: 1)<br>query `per-page`: integer (min: 1) (max: 50) | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Document`](#document)> } |
| GET | `/v1/documents/statuses` | `DocumentResource#statuses` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`DocumentStatus`](#documentstatus)> } |
| GET | `/v1/documents/{documentId}` | `DocumentResource#details` | Bearer token or `X-Api-Key` or `signer-access-code` query | path `documentId*`: string<br>query `expand`: Array<string (`"envelope_id"`, `"envelope"`)> | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Document`](#document) } |
| DELETE | `/v1/documents/{documentId}` | `DocumentResource#delete` | Bearer token or `X-Api-Key` | path `documentId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| PATCH | `/v1/documents/{documentId}` | `DocumentResource#rename` | Bearer token or `X-Api-Key` | path `documentId*`: string | required; `application/json` object { `name*`: string (max length: 255) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Document`](#document) } |
| GET | `/v1/documents/{documentId}/download/{artifactName}` | `DocumentResource#download` | Bearer token or `X-Api-Key` or `signer-access-code` query | path `documentId*`: string<br>path `artifactName*`: string (`"original"`, `"certificated"`, `"certificate-page"`, `"pades"`, `"bundle"`) | None | `200` `application/pdf` string (format: binary) |
| GET | `/v1/documents/{documentSignatureHash}/verify` | `DocumentResource#verify` | Public | path `documentSignatureHash*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`DocumentVerification`](#documentverification) } |
| GET | `/v1/accounts/{accountId}/documents/{documentId}/tags` | `DocumentResource#list_tags` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `documentId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Tag`](#tag)> } |
| PUT | `/v1/accounts/{accountId}/documents/{documentId}/tags` | `DocumentResource#replace_tags` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `documentId*`: string | required; `application/json` object { `tags`: Array<string> } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Tag`](#tag)> } |
| POST | `/v1/accounts/{accountId}/documents/{documentId}/tags` | `DocumentResource#append_tags` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `documentId*`: string | required; `application/json` object { `tags`: Array<string> } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Tag`](#tag)> } |
| DELETE | `/v1/accounts/{accountId}/documents/{documentId}/tags/{tagId}` | `DocumentResource#detach_tag` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `documentId*`: string<br>path `tagId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `detached`: boolean } } |
| GET | `/v1/accounts/{accountId}/embed-origins` | `AccountResource#list_embed_origins` | Bearer token or `X-Api-Key` | path `accountId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`EmbedOrigin`](#embedorigin)> } |
| POST | `/v1/accounts/{accountId}/embed-origins` | `AccountResource#create_embed_origin` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `application/json` object { `origin*`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`EmbedOrigin`](#embedorigin) } |
| PUT | `/v1/accounts/{accountId}/embed-origins/{originId}` | `AccountResource#update_embed_origin` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `originId*`: string | required; `application/json` object { `origin*`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`EmbedOrigin`](#embedorigin) } |
| DELETE | `/v1/accounts/{accountId}/embed-origins/{originId}` | `AccountResource#delete_embed_origin` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `originId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| POST | `/v1/documents/{documentId}/assignments/{assignmentId}/signers/{signerId}/embed-sessions` | `AssignmentResource#create_embed_session` | Bearer token or `X-Api-Key` | path `documentId*`: string<br>path `assignmentId*`: string<br>path `signerId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`EmbedSession`](#embedsession) } |
| POST | `/v1/embed/sessions/{token}/exchange` | `AssignmentResource#exchange_embed_session` | Public | path `token*`: string | optional; `application/json` object { `parent_origin`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`EmbedSessionExchange`](#embedsessionexchange) } |
| GET | `/v1/accounts/{accountId}/envelopes` | `EnvelopeResource#list` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `page`: integer (min: 1)<br>query `per-page`: integer (min: 1) (max: 50)<br>query `search`: string<br>query `status`: string (`"open"`, `"closed"`) | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`DocumentEnvelope`](#documentenvelope)> } |
| POST | `/v1/accounts/{accountId}/envelopes` | `EnvelopeResource#create` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>header `Idempotency-Key`: string | required; `application/json` [`EnvelopeCreateRequest`](#envelopecreaterequest) | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`DocumentEnvelope`](#documentenvelope) } |
| POST | `/v1/accounts/{accountId}/envelopes/estimate-cost` | `EnvelopeResource#estimate_cost` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `application/json` [`EnvelopeCreateRequest`](#envelopecreaterequest) | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`CostEstimate`](#costestimate) } |
| GET | `/v1/accounts/{accountId}/envelopes/{envelopeId}` | `EnvelopeResource#get` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `envelopeId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`DocumentEnvelope`](#documentenvelope) } |
| DELETE | `/v1/accounts/{accountId}/envelopes/{envelopeId}` | `EnvelopeResource#delete` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `envelopeId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| PATCH | `/v1/accounts/{accountId}/envelopes/{envelopeId}` | `EnvelopeResource#update` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `envelopeId*`: string | required; `application/json` object { `name`: string (min length: 1) (max length: 255); `message`: string or null; `document_ids`: Array<string> (min items: 1) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`DocumentEnvelope`](#documentenvelope) } |
| GET | `/v1/accounts/{accountId}/envelopes/{envelopeId}/activities` | `EnvelopeResource#activities` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `envelopeId*`: string<br>query `sort`: string<br>query `page`: integer (min: 1)<br>query `per-page`: integer (min: 1) (max: 50) | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`EnvelopeActivity`](#envelopeactivity)> } |
| GET | `/v1/accounts/{accountId}/envelopes/{envelopeId}/download/{artifactName}` | `EnvelopeResource#download` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `envelopeId*`: string<br>path `artifactName*`: string (`"original"`, `"certificated"`, `"certificate-page"`, `"pades"`, `"bundle"`) | None | `200` `application/zip` string (format: binary) |
| PUT | `/v1/accounts/{accountId}/envelopes/{envelopeId}/cancel` | `EnvelopeResource#cancel` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `envelopeId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<object { `id*`: string; `status*`: string; `cancelled*`: boolean }> } |
| PUT | `/v1/accounts/{accountId}/envelopes/{envelopeId}/signers/{signerId}/resend` | `EnvelopeResource#resend_notification` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `envelopeId*`: string<br>path `signerId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `is_sent*`: boolean; `envelope_id*`: string; `signer_id*`: string } } |
| POST | `/v1/accounts/{accountId}/envelopes/{envelopeId}/documents` | `EnvelopeResource#add_document` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `envelopeId*`: string | required; `application/json` [`EnvelopeDocumentRequest`](#envelopedocumentrequest) plus object { `max_total_credits`: number (min: 0) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`DocumentEnvelope`](#documentenvelope) } |
| DELETE | `/v1/accounts/{accountId}/envelopes/{envelopeId}/documents/{documentId}` | `EnvelopeResource#remove_document` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `envelopeId*`: string<br>path `documentId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`DocumentEnvelope`](#documentenvelope) } |
| GET | `/v1/accounts/{accountId}/fields` | `FieldResource#list` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `include_inactive`: boolean<br>query `include_standard`: boolean | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Field`](#field)> } |
| POST | `/v1/accounts/{accountId}/fields` | `FieldResource#create` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `application/json` object { `name*`: string; `type*`: string; `regex`: string or null; `is_required`: boolean } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Field`](#field) } |
| GET | `/v1/accounts/{accountId}/fields/{fieldId}` | `FieldResource#get` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `fieldId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Field`](#field) } |
| PUT | `/v1/accounts/{accountId}/fields/{fieldId}` | `FieldResource#update` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `fieldId*`: string | required; `application/json` object { `name`: string; `regex`: string or null; `is_active`: boolean } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Field`](#field) } |
| DELETE | `/v1/accounts/{accountId}/fields/{fieldId}` | `FieldResource#delete` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `fieldId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| POST | `/v1/accounts/{accountId}/fields/{fieldId}/validate` | `FieldResource#validate` | Bearer token or `X-Api-Key` or `signer-access-code` query | path `accountId*`: string<br>path `fieldId*`: string | required; `application/json` object { `value*`: any } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`FieldValidation`](#fieldvalidation) } |
| POST | `/v1/accounts/{accountId}/fields/validate-multiple` | `FieldResource#validate_multiple` | Bearer token or `X-Api-Key` or `signer-access-code` query | path `accountId*`: string | required; `application/json` Array<object { `field_id*`: string; `value*`: any }> | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`FieldValidationResult`](#fieldvalidationresult)> } |
| GET | `/v1/field-types` | `FieldResource#types` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`FieldType`](#fieldtype)> } |
| GET | `/v1/users/self/mfa` | `AuthResource#mfa_methods` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `methods`: Array<object { `id`: string; `type`: string; `label`: string; `confirmed_at`: string (format: date-time); `last_used_at`: string (format: date-time) }>; `recovery_codes_remaining`: integer } } |
| POST | `/v1/users/self/mfa/totp` | `AuthResource#start_totp_enrollment` | Bearer token or `X-Api-Key` | None | optional; `application/json` object { `label`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `id`: string; `secret`: string; `provisioning_uri`: string } } |
| PUT | `/v1/users/self/mfa/totp/confirm` | `AuthResource#confirm_totp_enrollment` | Bearer token or `X-Api-Key` | None | required; `application/json` object { `id*`: string; `code*`: string; `password`: string (format: password); `reauth_code`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `recovery_codes`: Array<string> } } |
| POST | `/v1/users/self/mfa/recovery-codes` | `AuthResource#regenerate_recovery_codes` | Bearer token or `X-Api-Key` | None | required; `application/json` object { `password`: string (format: password); `code`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `recovery_codes`: Array<string> } } |
| DELETE | `/v1/users/self/mfa/{customId}` | `AuthResource#delete_mfa_method` | Bearer token or `X-Api-Key` | path `customId*`: string | required; `application/json` object { `password`: string (format: password); `code`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `is_mfa_enabled`: boolean } } |
| GET | `/v1/accounts/{accountId}/notification-policy` | `AccountResource#notification_policy` | Bearer token or `X-Api-Key` | path `accountId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`NotificationPolicy`](#notificationpolicy) } |
| PUT | `/v1/accounts/{accountId}/notification-policy` | `AccountResource#update_notification_policy` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `application/json` object { `events`: [`NotificationPolicyEvents`](#notificationpolicyevents); `owners_receive_all`: boolean } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`NotificationPolicy`](#notificationpolicy) } |
| GET | `/v1/users/self/notification-preferences` | `UserResource#notification_preferences` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`NotificationPreferences`](#notificationpreferences) } |
| PUT | `/v1/users/self/notification-preferences` | `UserResource#update_notification_preferences` | Bearer token or `X-Api-Key` | None | required; `application/json` [`NotificationPreferences`](#notificationpreferences) | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`NotificationPreferences`](#notificationpreferences) } |
| POST | `/v1/oauth/token` | `OAuthResource#token` | Public | None | required; `application/x-www-form-urlencoded` [`OAuthTokenRequest`](#oauthtokenrequest)<br>`application/json` [`OAuthTokenRequest`](#oauthtokenrequest) | `200` `application/json` object { `access_token`: string; `issued_token_type`: string; `token_type`: string; `expires_in`: integer; `refresh_token`: string or null; `scope`: string; `id_token`: string or null } |
| POST | `/v1/oauth/revoke` | `OAuthResource#revoke` | Public | None | required; `application/x-www-form-urlencoded` [`OAuthRevokeRequest`](#oauthrevokerequest)<br>`application/json` [`OAuthRevokeRequest`](#oauthrevokerequest) | `200` Revoked |
| GET | `/v1/oauth/userinfo` | `OAuthResource#userinfo` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` object { `sub`: string; `name`: string or null; `email`: string or null (format: email); `email_verified`: boolean or null } |
| GET | `/v1/documents/{documentId}/thumbnail` | `DocumentResource#thumbnail` | Bearer token or `X-Api-Key` or `signer-access-code` query | path `documentId*`: string<br>query `artifact`: string | None | `200` `image/*` string (format: binary) |
| GET | `/v1/documents/{documentId}/pages/{pageId}/download` | `DocumentResource#download_page` | Bearer token or `X-Api-Key` or `signer-access-code` query | path `documentId*`: string<br>path `pageId*`: string<br>query `artifact`: string | None | `200` `image/*` string (format: binary) |
| GET | `/v1/public/documents/{documentId}` | `DocumentResource#public_info` | Public | path `documentId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Document`](#document) } |
| PUT | `/v1/public/documents/{documentId}/send-token` | `DocumentResource#send_token` | Public | path `documentId*`: string | required; `application/json` object { `channel*`: string (`"email"`); `recipient*`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `document`: object { `resource`: string; `id`: string; `name`: string; `page_count`: integer; `created_by`: string }; `channel`: string; `recipient`: string } } |
| GET | `/v1/users/self/push-preferences` | `UserResource#push_preferences` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`PushPreferences`](#pushpreferences) } |
| PUT | `/v1/users/self/push-preferences` | `UserResource#update_push_preferences` | Bearer token or `X-Api-Key` | None | required; `application/json` [`PushPreferences`](#pushpreferences) | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`PushPreferences`](#pushpreferences) } |
| GET | `/v1/accounts/{accountId}/signers` | `SignerResource#list` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `search`: string<br>query `page`: integer (min: 1)<br>query `per-page`: integer (min: 1) (max: 50) | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Signer`](#signer)> } |
| POST | `/v1/accounts/{accountId}/signers` | `SignerResource#create` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `application/json` object { `full_name*`: string; `email`: string (format: email); `whatsapp_phone_number`: string; `government_id`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Signer`](#signer) } |
| GET | `/v1/accounts/{accountId}/signers/{signerId}` | `SignerResource#get` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `signerId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Signer`](#signer) } |
| PUT | `/v1/accounts/{accountId}/signers/{signerId}` | `SignerResource#update` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `signerId*`: string | required; `application/json` object { `full_name`: string; `email`: string (format: email); `whatsapp_phone_number`: string; `government_id`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Signer`](#signer) } |
| DELETE | `/v1/accounts/{accountId}/signers/{signerId}` | `SignerResource#delete` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `signerId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| GET | `/v1/signers/self` | `SignerResource#self_data` | `signer-access-code` query | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`SignerSelf`](#signerself) } |
| GET | `/v1/sign/theme` | `SignerResource#theme` | `signer-access-code` query | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`AccountTheme`](#accounttheme) } |
| GET | `/v1/sign/logo` | `SignerResource#download_logo` | `signer-access-code` query | None | None | `200` `image/*` string (format: binary) |
| GET | `/v1/signers/identity-verification` | `SignerResource#identity_verification` | `signer-access-code` query | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `can_start`: boolean; `status`: string or null; `url`: string or null; `expires_at`: string or null (format: date-time); `completed_at`: string or null (format: date-time) } } |
| POST | `/v1/signers/identity-verification` | `SignerResource#start_identity_verification` | `signer-access-code` query | None | required; `application/json` object { `consent*`: boolean } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `id`: string; `url`: string; `expires_at`: string or null (format: date-time) } } |
| GET | `/v1/signers/{signerId}/document` | `SignerDocumentResource#current` | `signer-access-code` query | path `signerId*`: string<br>query `expand`: Array<string (`"envelope"`)> | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`SigningDocument`](#signingdocument) } |
| GET | `/v1/sign` | `AssignmentResource#signer_document` | `signer-access-code` query | query `has_accepted_terms`: boolean<br>query `expand`: Array<string (`"envelope"`)><br>query `document_id`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`SigningDocument`](#signingdocument) } |
| POST | `/v1/documents/{documentId}/assignments/{assignmentId}` | `AssignmentResource#sign` | `signer-access-code` query | path `documentId*`: string<br>path `assignmentId*`: string | required; `application/json` Array<object { `itemId*`: string; `fieldId*`: string; `pageId*`: string; `value*`: string }> | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object } |
| PUT | `/v1/documents/{documentId}/assignments/{assignmentId}/reject` | `AssignmentResource#decline` | `signer-access-code` query | path `documentId*`: string<br>path `assignmentId*`: string | required; `application/json` object { `decline_reason*`: string (max length: 2000) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| PUT | `/v1/signers/documents/sign-multiple` | `SignerDocumentResource#sign_multiple` | `signer-access-code` query | None | required; `application/json` object { `document_ids*`: Array<string> } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| PUT | `/v1/signers/documents/decline-multiple` | `SignerDocumentResource#decline_multiple` | `signer-access-code` query | None | required; `application/json` object { `document_ids*`: Array<string>; `decline_reason*`: string (max length: 2000) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| POST | `/v1/verify` | `SignerResource#verify_email` | `signer-access-code` query | None | required; `application/json` object { `verification-code*`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| PUT | `/v1/documents/{documentId}/signers/confirm-data` | `SignerResource#confirm_data` | `signer-access-code` query | path `documentId*`: string | required; `application/json` object { `email`: string (format: email); `whatsapp_phone_number`: string; `has_accepted_terms`: boolean } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| PUT | `/v1/signers/accept-terms` | `SignerResource#accept_terms` | `signer-access-code` query | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `full_name*`: string; `email*`: string or null (format: email); `has_accepted_terms*`: boolean } } |
| POST | `/v1/signature` | `SignerResource#upload_signature` | `signer-access-code` query | query `type`: string<br>query `reuse`: boolean | required; `image/png` string (format: binary) | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| GET | `/v1/signature/{signatureType}` | `SignerResource#download_signature` | `signer-access-code` query | path `signatureType*`: string | None | `200` `image/*` string (format: binary) |
| GET | `/v1/signers/{signerId}/documents` | `SignerDocumentResource#list` | `signer-access-code` query or Bearer token or `X-Api-Key` | path `signerId*`: string<br>query `envelope_id`: string<br>query `page`: integer (min: 1)<br>query `per-page`: integer (min: 1) (max: 50) | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Document`](#document)> } |
| GET | `/v1/signers/{signerId}/documents/search` | `SignerDocumentResource#search` | `signer-access-code` query or Bearer token or `X-Api-Key` | path `signerId*`: string<br>query `envelope_id`: string<br>query `search`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Document`](#document)> } |
| GET | `/v1/signers/{signerId}/documents/{documentId}/download/{artifactName}` | `SignerDocumentResource#download` | `signer-access-code` query | path `signerId*`: string<br>path `documentId*`: string<br>path `artifactName*`: string (`"original"`) | None | `200` `application/pdf` string (format: binary) |
| POST | `/v1/sign/certified-copy` | `SignerDocumentResource#send_certified_copy` | `signer-access-code` query | None | optional; `application/json` object { `document_id`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `available`: boolean; `notification_method`: string (`"Email"`, `"Whatsapp"`); `resends_left`: integer or null; `sent_to`: string } } |
| GET | `/v1/signers/downloads/{token}` | `SignerDocumentResource#download_certified_copy` | Public | path `token*`: string | None | `200` `application/pdf` string (format: binary) |
| POST | `/v1/signers/downloads/{token}/resend` | `SignerDocumentResource#resend_certified_copy` | Public | path `token*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `available`: boolean; `notification_method`: string (`"Email"`, `"Whatsapp"`); `resends_left`: integer or null; `sent_to`: string } } |
| POST | `/v1/authentication/social-login` | `AuthResource#social_login` | Public | None | required; `application/json` object { `provider*`: string (`"google"`); `token*`: string; `has_accepted_terms*`: boolean } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`AuthSession`](#authsession) } |
| POST | `/v1/auth/link-social-login` | `AuthResource#link_social_login` | Bearer token or `X-Api-Key` | None | required; `application/json` object { `provider*`: string (`"google"`); `token*`: string } | `200` `application/json` [`Envelope`](#envelope) |
| GET | `/v1/accounts/{accountId}/stats` | `AccountResource#stats` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `granularity`: string (`"monthly"`, `"daily"`)<br>query `month`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`DocumentStatsRow`](#documentstatsrow)> } |
| GET | `/v1/users/self/stats` | `UserResource#stats` | Bearer token or `X-Api-Key` | query `granularity`: string (`"monthly"`, `"daily"`)<br>query `month`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`DocumentStatsRow`](#documentstatsrow)> } |
| GET | `/v1/accounts/{accountId}/tags` | `TagResource#list` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `search`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Tag`](#tag)> } |
| POST | `/v1/accounts/{accountId}/tags` | `TagResource#create` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `application/json` object { `name*`: string; `color`: string or null } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Tag`](#tag) } |
| PUT | `/v1/accounts/{accountId}/tags/{tagId}` | `TagResource#update` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `tagId*`: string | required; `application/json` object { `name`: string; `color`: string or null } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Tag`](#tag) } |
| DELETE | `/v1/accounts/{accountId}/tags/{tagId}` | `TagResource#delete` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `tagId*`: string<br>query `force`: boolean | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `deleted`: boolean } } |
| GET | `/v1/accounts/{accountId}/templates` | `TemplateResource#list` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `search`: string<br>query `page`: integer (min: 1)<br>query `per-page`: integer (min: 1) (max: 50) | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Template`](#template)> } |
| POST | `/v1/accounts/{accountId}/templates/{templateId}/documents` | `DocumentResource#create_from_template` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `templateId*`: string<br>header `Idempotency-Key`: string | required; `application/json` object { `signers*`: Array<object { `role_id*`: string; `id`: string; `email`: string; `name`: string; `whatsapp_phone_number`: string; `verification_method`: string (`"Email"`, `"Whatsapp"`, `"DigitalCertificate"`, `"IdDocumentFaceMatchBasic"`); `notification_methods`: Array<string>; `embedded`: boolean; `step`: integer }>; `editor_fields`: Array<object { `field_id*`: string; `value*`: string }>; `name`: string; `message`: string; `expires_at`: string (format: date-time); `tags`: Array<string>; `max_total_credits`: number } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Document`](#document) } |
| POST | `/v1/accounts/{accountId}/templates/{templateId}/documents/estimate-cost` | `DocumentResource#estimate_cost_from_template` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `templateId*`: string | required; `application/json` object { `signers*`: Array<object { `role_id*`: string; `verification_method`: string (`"Email"`, `"Whatsapp"`, `"DigitalCertificate"`, `"IdDocumentFaceMatchBasic"`); `notification_methods`: Array<string> }> } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`CostEstimate`](#costestimate) } |
| GET | `/v1/users/self` | `UserResource#me` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`AuthUser`](#authuser) } |
| GET | `/v1/users/api-keys` | `AuthResource#get_api_key` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`ApiKey`](#apikey) } |
| POST | `/v1/users/api-keys` | `AuthResource#create_api_key` | Bearer token or `X-Api-Key` | None | required; `application/json` object { `password*`: string (format: password) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`ApiKey`](#apikey) } |
| DELETE | `/v1/users/api-keys` | `AuthResource#delete_api_key` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| GET | `/v1/accounts/{accountId}/webhooks/subscriptions` | `WebhookResource#get` | Bearer token or `X-Api-Key` | path `accountId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`WebhookSubscription`](#webhooksubscription) } |
| PUT | `/v1/accounts/{accountId}/webhooks/subscriptions` | `WebhookResource#register` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `application/json` object { `events*`: Array<string>; `is_active*`: boolean; `url*`: string (format: uri); `email*`: string (format: email) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`WebhookSubscription`](#webhooksubscription) } |
| PUT | `/v1/accounts/{accountId}/webhooks/inactivate` | `WebhookResource#inactivate` | Bearer token or `X-Api-Key` | path `accountId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`WebhookSubscription`](#webhooksubscription) } |
| GET | `/v1/webhooks/event-types` | `WebhookResource#list_event_types` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`WebhookEventType`](#webhookeventtype)> } |
| GET | `/v1/accounts/{accountId}/webhooks` | `WebhookResource#list_dispatches` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `endpoint_id`: string<br>query `event`: string<br>query `delivered`: string (`"true"`, `"false"`)<br>query `from`: integer<br>query `to`: integer<br>query `page`: integer<br>query `per-page`: integer (min: 1) (max: 50) | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`WebhookDispatch`](#webhookdispatch)> } |
| POST | `/v1/accounts/{accountId}/webhooks/{historyId}/retry` | `WebhookResource#retry_dispatch` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `historyId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`WebhookDispatch`](#webhookdispatch) } |
| GET | `/v1/accounts/{accountId}/webhooks/endpoints` | `WebhookResource#list_endpoints` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `url`: string (format: uri) | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`WebhookEndpoint`](#webhookendpoint)> } |
| POST | `/v1/accounts/{accountId}/webhooks/endpoints` | `WebhookResource#create_endpoint` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `application/json` object { `url*`: string (format: uri); `email*`: string (format: email); `events*`: Array<string>; `name`: string; `is_active`: boolean; `signing_enabled`: boolean } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`WebhookEndpoint`](#webhookendpoint) plus object { `secret`: string } } |
| DELETE | `/v1/accounts/{accountId}/webhooks/endpoints` | `WebhookResource#delete_endpoint_by_url` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `url*`: string (format: uri) | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| GET | `/v1/accounts/{accountId}/webhooks/endpoints/{endpointId}` | `WebhookResource#get_endpoint` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `endpointId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`WebhookEndpoint`](#webhookendpoint) } |
| PUT | `/v1/accounts/{accountId}/webhooks/endpoints/{endpointId}` | `WebhookResource#update_endpoint` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `endpointId*`: string | required; `application/json` object { `url`: string (format: uri); `email`: string (format: email); `events`: Array<string>; `name`: string; `is_active`: boolean; `signing_enabled`: boolean } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`WebhookEndpoint`](#webhookendpoint) plus object { `secret`: string } } |
| DELETE | `/v1/accounts/{accountId}/webhooks/endpoints/{endpointId}` | `WebhookResource#delete_endpoint` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `endpointId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| GET | `/v1/accounts/{accountId}/webhooks/endpoints/{endpointId}/secret` | `WebhookResource#endpoint_secret` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `endpointId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`WebhookEndpointSecret`](#webhookendpointsecret) } |
| POST | `/v1/accounts/{accountId}/webhooks/endpoints/{endpointId}/secret/rotate` | `WebhookResource#rotate_endpoint_secret` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `endpointId*`: string | optional; `application/json` object { `keep_previous`: boolean } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`WebhookEndpointSecret`](#webhookendpointsecret) plus object { `previous_secret_expires_at`: string (format: date-time) } } |
| POST | `/v1/accounts/{accountId}/webhooks/endpoints/{endpointId}/test` | `WebhookResource#test_endpoint` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `endpointId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`WebhookDispatch`](#webhookdispatch) } |
| GET | `/.well-known/oauth-protected-resource` | `OAuthResource#protected_resource_metadata` | Public | None | None | `200` `application/json` object { `resource`: string (format: uri); `authorization_servers`: Array<string (format: uri)>; `scopes_supported`: Array<string>; `bearer_methods_supported`: Array<string> } |
| GET | `/v1/documents/{documentId}/assignments/{assignmentId}/whatsapp-notifications` | `AssignmentResource#whatsapp_notifications` | Bearer token or `X-Api-Key` | path `documentId*`: string<br>path `assignmentId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`WhatsappNotification`](#whatsappnotification)> } |

## Error responses

OAuth endpoints are the exception to everything in this section: `/v1/oauth/token` and
`/v1/oauth/revoke` report failures as the flat RFC 6749 §5.2 object `{error, error_description}`,
and `/v1/oauth/userinfo` can report a framework error envelope. Both raise `Assinafy::OAuthError`, a subclass
of `Assinafy::ApiError` that exposes `#error` and `#error_description` separately rather than
flattening them into one message.


Assinafy can return errors as an application envelope:

```json
{
  "status": 404,
  "data": null,
  "message": "Resource not found."
}
```

Framework errors use this shape:

```json
{
  "name": "Not Found",
  "message": "Resource not found.",
  "code": 0,
  "status": 404
}
```

Typical statuses are `400` for invalid parameters or bodies, `401` for missing or invalid authentication, `404`
for an unavailable resource, `409` for a state conflict, and `500` for a server failure. All non-success responses
raise `Assinafy::ApiError`:

- `status_code` contains the HTTP or envelope status.
- `message` uses the API's `message`, `error`, or `name` value.
- `response_data` preserves the parsed response body.
- `error_name` exposes `name`; `error_code` exposes numeric framework codes or actionable codes such as
  `PlanRestricted`, `InsufficientScope`, `CreditCeilingExceeded`, `DocumentNotReady` and `ContractChanged`.
  `response_data['errors']` preserves field-level `{ field, code, message }` entries.
- `context` contains `status_code` and `response_data` for structured logging or support diagnostics, plus
  `www_authenticate` when the response carries that header.
- `rate_limit` returns `{ limit:, remaining:, reset: }` from the `X-Rate-Limit-Limit`, `X-Rate-Limit-Remaining`
  and `X-Rate-Limit-Reset` headers (reset in seconds), and `retry_after` returns the `Retry-After` seconds of a
  `429 Too Many Requests`; both are `nil` when the headers are absent. Wait at least `retry_after` seconds before
  retrying. Requests are limited per minute, per user when authenticated and per IP address otherwise.

Transport, timeout, and TLS failures raise `Assinafy::NetworkError`; caller-side validation failures raise
`Assinafy::ValidationError` before a request is sent.

## Operational notes

### Template operations

The sandbox and SDK support these five template operations. Their request and response behavior is documented
here so applications can use the complete template lifecycle. Confirm availability in the target Assinafy
environment before making these operations part of a critical workflow.

| Method | Path | Ruby SDK method | Authentication | Request / response |
| --- | --- | --- | --- | --- |
| GET | `/v1/accounts/{account_id}/templates/{template_id}` | `TemplateResource#get` | Bearer token or `X-Api-Key` | No request body; returns an unwrapped `Template`-shaped object. |
| POST | `/v1/accounts/{account_id}/templates` | `TemplateResource#create` | Bearer token or `X-Api-Key` | Multipart PDF upload; returns an unwrapped `Template`-shaped object. |
| PUT | `/v1/accounts/{account_id}/templates/{template_id}` | `TemplateResource#update` | Bearer token or `X-Api-Key` | JSON partial update; returns an unwrapped `Template`-shaped object. |
| DELETE | `/v1/accounts/{account_id}/templates/{template_id}` | `TemplateResource#delete` | Bearer token or `X-Api-Key` | No request body; returns `nil` on success. |
| GET | `/v1/accounts/{account_id}/templates/{template_id}/pages/{page_id}/download` | `TemplateResource#download_page` | Bearer token or `X-Api-Key` | No request body; returns binary image bytes. |

### Assignment listing

`GET /v1/assignments` is scoped by the camelCase `accountId` query parameter. `AssignmentResource#list` supplies
it from the client default or the per-call override.

### Assignment optional fields

`message` must be a string; `expires_at` must be an ISO 8601 timestamp with a timezone at least one hour in the future, and `copy_receivers` must be an array of non-empty signer IDs.
`AssignmentResource.build_payload` rejects other shapes locally, so `Client#upload_and_request_signatures`
fails before it uploads a document or creates signers.

### Base URL

`base_url` must be an absolute `http`/`https` URL with a host. Other schemes, scheme-less hosts, and relative
paths raise `Assinafy::ValidationError` at construction rather than sending credentials to them.
`Configuration#base_url=` and `#timeout=` apply the same validation. The `User-Agent` header is set on every
request.

### Document upload and tags

`DocumentResource#upload` sends only the multipart `file` part; the API names the document after the uploaded
file name. Rename it with `DocumentResource#rename`. Documents and templates are limited to 25 MB, checked
locally together with the `.pdf` extension and `%PDF-` header.

`DocumentResource#list` accepts `tags` as a comma-separated String or an Array of tag IDs, which the SDK joins
with commas; matching documents carry every listed tag. `DocumentResource#replace_tags` and `#append_tags` accept
arrays of tag IDs. Use a tag ID with `DocumentResource#detach_tag`.

### Contract tracking

Contract terms belong to an existing document; setting terms never uploads, sends, or signs the document.
`ContractResource#update` creates or partially changes the terms. Explicit `nil` values remain JSON null so they
clear nullable fields. To record a signed amendment, renewal, or termination instrument, upload that document and
set its `parent_document_id`, `relation_type`, and changed terms; the delta applies after the instrument is
certificated. `#get` reads the terms or an instrument, and `#related` always reads the root family.

The hourly lifecycle moves active contracts through notice, expiry, and automatic renewal. `#renew` starts the
next term immediately; sending the current `term` makes a lost-response retry safe. `#terminate` closes the
contract and records its optional reason. Writers can send the `updated_at` they read as an optimistic-lock
precondition; the API refuses a stale write with `409`. Reads remain available without the contract-tracking
plan, while writes answer `403` when the plan lacks the feature. OAuth reads require `documents:read`, and writes
require `documents:write`.

### KPI statistics

`UserResource#stats` and `AccountResource#stats` validate `granularity` (`monthly` or `daily`) and `month`
(`YYYY-MM`) locally before sending. Daily statistics require `month`.

### OAuth response shapes

`/v1/oauth/token`, `/v1/oauth/revoke`, and `/v1/oauth/userinfo` deliberately do not use the
`{status, data, message}` envelope: no standard OAuth or OIDC client would look for `access_token`
or `error` inside a `data` key. `/.well-known/oauth-protected-resource` returns bare RFC 8615
metadata for the same reason. `OAuthResource` returns all four bodies unchanged.

`/v1/oauth/token` and `/v1/oauth/revoke` are unauthenticated routes that identify the client
through `client_id` in the body, so the SDK strips `X-Api-Key`/`Authorization` from them.
`OAuthResource#authorization_server_metadata` reaches a different host
(`auth.assinafy.com.br`) and is stripped for the same reason. A URL override must be an absolute HTTPS URL
without userinfo or fragment; anything else raises `Assinafy::ValidationError`.

`/.well-known/oauth-protected-resource` is served from the host root, outside the `/v1` prefix
that `base_url` carries.


### Token refresh

The SDK does not refresh access tokens automatically. Persist `expires_in` alongside the token and
call `OAuthResource#refresh` before expiry. A refresh token is issued only when `offline_access` was
both requested and consented.

Every refresh returns a new refresh token, valid for another 30 days, and retires the one sent, so a
connection only expires after 30 days without a refresh. Reusing a retired refresh token ends the
whole connection. Store the new refresh and access tokens before using either, rebuild the client with
the new access token, and run one refresh at a time per connection. `OAuthResource#refresh`, and
`#token` with the `refresh_token` grant, raise `Assinafy::Error` rather than return a success whose
`refresh_token` is missing, blank, or the one sent; handle that like `invalid_grant`.

The SDK never retries token requests; do not add middleware that does. After an ambiguous failure — a
timeout, a reset connection, a `5xx` — the server may have rotated the token without the response
arriving. Re-read the stored refresh token: if it is still the one you sent, never send it again; ask
the user to connect again. Proceed only if another worker has since stored a different one. Only a
failure that provably happened before the request was sent (DNS resolution, a refused connection, a
failed TLS handshake) is safe to retry. On an API `401`, refresh once; if that fails, or on
`invalid_grant`, ask the user to connect again.

When a user disconnects, revoke the refresh token in storage at that moment with `OAuthResource#revoke`,
then delete the stored tokens. Revoking a rotated token also answers `200`, so revoking a stale copy can
look successful while the connection stays active.

### Verification and notification methods

Verification and notification methods are coupled per signer: the omitted side is inferred from the other, and
when both are omitted both are `Email`. Exactly one notification method is allowed. Allowed pairs: `Email` with
`Email`, `Whatsapp` with `Whatsapp`, and `DigitalCertificate` or `IdDocumentFaceMatchBasic` with either. `Email` costs 0 credits; `Whatsapp`
costs 0.45 credits (its WhatsApp notification, paid plans only); `DigitalCertificate` costs 0.5 credits per signer
on top of its notification, shown in cost estimates under the breakdown code `SignatureDigitalCertificate`.

### Digital-certificate signing

`DigitalCertificate` has the signer sign with their own ICP-Brasil certificate (A1 or A3) through the Web PKI
browser extension, producing a qualified PAdES signature. It requires the Digital Certificate account feature, a
CPF or CNPJ in the signer's `government_id` (accepted by both `SignerResource#create` and `#update`), a
`method: 'virtual'` assignment, and that the signer is alone in its signing step. `AssignmentResource#create` and
`#estimate_cost` reject any other assignment method with `ValidationError`; its stable
`errors[:code]` is `digital_certificate_requires_virtual`. A CPF requires that person's certificate (an e-CPF, or
an e-CNPJ naming them as legal representative); a CNPJ requires an e-CNPJ for that company, from any of its
representatives.

A template with positioned signer fields creates a collect assignment, so it cannot be used with a
`DigitalCertificate` signer. Use a template without positioned signer fields for certificate signing.

Certificate signers complete the signature in Assinafy's hosted signing flow, reached through the assignment's
`signing_urls`. The SDK does not wrap the two-step Web PKI handshake (`/signers/certificate/start`,
`/signers/certificate/complete`), whose authentication and request/response schemas are not part of the OpenAPI
contract. Once the flow completes, the `pades` artifact returns the qualified signature.

### Biometric identity verification

`IdDocumentFaceMatchBasic` requires its account feature and a valid CPF in the signer's `government_id`.
It uses government ID photos, a photo holding the ID and liveness, and adds a per-signer fee to the chosen
Email or Whatsapp notification. Call `estimate_cost` or `estimate_cost_from_template` for the current total.
Both assignment methods and template generation accept this verification method.

With the signer access code, read `signers.identity_verification`; after the signer explicitly consents to
biometric processing, call `signers.start_identity_verification(consent: true, signer_access_code: code)`.
Open the returned capture URL unchanged, including its fragment; it is a bearer link, so keep it out of logs
and browser storage. The status response backfills pending provider decisions. `can_start` is true only before
any session or after Expired; Pending, InReview, Approved, Declined and Abandoned cannot restart. A restart
replaces an Expired session without another charge. Declined or Abandoned requires a new document and assignment.

During InReview the signer may view, confirm data and sign. Certification waits for account approval; once all
signers sign, the document can be `pending_identity_review`. Read `assignments.identity_review`, download only
names from its `images` with `identity_review_image`, and submit `decide_identity_review(decision: 'Approved')`
or `decision: 'Rejected'` while the document is pending_signature or pending_identity_review. Rejection cancels
the document and notifies signers and copy receivers. Optional `note:` (at most 2000 characters) is recorded in
activities and sent to the provider; it is never shown to the signer. Images are fetched from the provider,
available only during InReview, and must not be cached. Evidence images and decisions require an API key or user session; third-party OAuth applications
can read the review summary with `documents:read`, but cannot fetch images or decide it. The review retains summaries, with `evidence_available`
false when none is retained or fetched. Direct approvals expose evidence through the signer_identity_verified
activity instead. Observe signer_identity_review_required, signer_identity_review_approved,
signer_identity_review_rejected, signer_identity_verified and signer_identity_verification_failed events.

### Webhook endpoints and deliveries

An account can have 1 webhook endpoint, or up to 3 on paid plans; each has a distinct URL, its own events, and its
own signing setting, and every active endpoint subscribed to an event receives it. Creation with
`signing_enabled: true` returns a `secret` once: store it immediately. OAuth apps cannot read it later, but can rotate it with `webhooks:write`;
store the newly returned secret. `keep_previous: true` retains the old secret for 24 hours of dual signing. `#list_endpoints(url: registered_url)` finds an exact URL match and
`#delete_endpoint_by_url(registered_url)` deletes that endpoint, returning `nil`. `WebhookResource#create_endpoint`
and `#update_endpoint` accept only `url`, `email`, `events`, `name`, `is_active`, and `signing_enabled`.
`#register`, `#get`, and `#inactivate` (`/webhooks/subscriptions`, `/webhooks/inactivate`) act on the account's
oldest endpoint; `#register` accepts only `url`, `email`, `events`, and `is_active`. New or changed endpoint URLs
must be absolute HTTPS URLs; the SDK rejects other schemes locally, while the API also refuses private, loopback,
link-local, and other reserved destination addresses.

Each delivery is a JSON `POST` carrying `webhook-id` (stable across attempts of one event to one endpoint; use it to
deduplicate), `webhook-timestamp` (Unix seconds), and, when signing is enabled, `webhook-signature`. Any `2xx` is
success. An event gets up to 6 attempts, about 10 minutes apart, for network failures, timeouts, `408`, `429` or `5xx`;
other failures are final. After 10 failed deliveries the endpoint pauses. Probes run after 3 minutes, then 15,
then 60, then every 6 hours; success resumes delivery of missed events oldest first. `WebhookResource#retry_dispatch` forces a
redelivery, and `#list_dispatches` filters by `endpoint_id`. The body is a [`WebhookEvent`](#webhookevent).

Signatures follow the [Standard Webhooks](https://www.standardwebhooks.com) specification: `webhook-signature`
holds space-separated `v1,<base64 HMAC-SHA256>` entries over `{webhook-id}.{webhook-timestamp}.{raw body}`, keyed
with the base64-decoded part of the secret after `whsec_`. `WebhookVerifier#verify_delivery(raw_body, headers,
tolerance: 300, now: Time.now.to_i)` checks them in constant time and rejects timestamps more than `tolerance`
seconds from `now`. It accepts Rails `request.headers`, a Rack env (`HTTP_WEBHOOK_ID`), or a plain Hash, and
returns `false` rather than raising. `WebhookVerifier#verify(raw_body, hex_signature)` remains for receivers whose
own gateway signs bodies with a hex HMAC-SHA256.

### Envelopes, embedding and downloads

`client.envelopes` groups up to 20 existing processed documents and 20 signers. Create with `name`,
`signers: [{ id: ... }]` and `documents: [{ id: ..., signer_ids: [...] }]`; each document retains its own
assignment and status. Every listed signer must be on a document. Certificate signers are alone on each of their
virtual documents; collect documents require positioned fields for exactly their `signer_ids`.
`estimate_cost` checks the same body without sending or charging. `create(..., idempotency_key:)` deduplicates
lost-response retries within the workspace. Keep the key for that logical creation; deleting the envelope also
removes its idempotency result. `max_total_credits` belongs on the envelope creation body, or on `add_document`;
it is not a per-document creation field. `update(message: nil)` clears the message; `document_ids` reorders all
its documents. Cancel notifies recipients, remove-document cancels that open document, and delete requires the
envelope to be closed and preserves its documents. Downloads return ZIP bytes.

Embedded signing requires the Embed feature and API-key/user-session authentication; third-party OAuth cannot
manage origins or create sessions. Register exact origins through `accounts.create_embed_origin`, mark an
Email/Whatsapp signer `embedded: true`, then call `assignments.create_embed_session`. Load its returned URL in
an iframe within five minutes. `exchange_embed_session` is normally called by Assinafy's embed page; its token
is consumed even on a `409`. It sends no workspace credentials and is never retried by the SDK.

`signer_documents.download` requires `signer_access_code:` and defaults to `original`; the published route serves
only the original while the code is active. Explicit historical artifact arguments remain accepted by the SDK,
with the API deciding availability. Use `send_certified_copy` to send a fresh link to the signing contact,
`download_certified_copy` for PDF bytes (optional `pades: true`), and `resend_certified_copy` for an expired link.
No workspace credentials are sent. Download links last seven days initially and 30 minutes when resent;
expired-link `302` responses raise `ApiError` and are not followed. The signing code closes 30 minutes after the
signer finishes all their documents. Signing summary/branding and certified-copy delivery remain available;
other signer calls can answer `410`.

### Templates and spending limits

`documents.create_from_template` accepts a role's existing signer `id`, or `email` with an optional `name` and
WhatsApp number to reuse/create the signer. A copy receiver's method and step are ignored upstream. Editor
fields need non-empty values. Creation returns an uploaded document with `assignment: nil`; follow document
status or webhooks until `pending_signature` or `failed`. `wait_until_ready` waits for document metadata and may
return before a template's assignment exists. Pass `idempotency_key` in the payload or options Hash (options take precedence) to avoid
creating duplicate documents. Assignment, template and envelope creation accept `max_total_credits`; a price
above it answers `409` with `CreditCeilingExceeded`. Template processing may fail later if the cost increases,
without charging. `accounts.usage` reports balances and `accounts.get(expand: 'signing_features')` reports the
available signing features. Usage is not available to third-party OAuth apps.

### Notifications and document reads

`users.push_preferences` and `update_push_preferences` manage eight personal phone-push flags, independently of
email preferences. `accounts.notification_policy` reads workspace event rules; owners change partial rules with
`update_notification_policy`. OAuth applications cannot access these personal/workspace notification settings.
`webhooks.test_endpoint` sends an actual test delivery, even to a paused or inactive endpoint.

`documents.details/get(..., expand:)` accepts `envelope_id` and `envelope`; list/search accept `envelope_id`.
`thumbnail` and `download_page` accept `artifact: 'certificated'` for signed renders, which must not be cached.
Document activities accept sort/page/per_page; `activities` preserves the Array return, and `activities_page`
returns pagination metadata. Envelope activities are always paginated.

## SDK-only helpers and aliases

These public functions do not map one-to-one to an API operation. Their source comments provide parameter,
return-value, and usage details.

| Public function | Purpose | Source documentation |
| --- | --- | --- |
| `Assinafy::Client.new` | Construct a client with keyword configuration. | [`client.rb`](../lib/assinafy/client.rb) |
| `Assinafy::Client.create` | Construct a client from positional API-key and account arguments. | [`client.rb`](../lib/assinafy/client.rb) |
| `Assinafy::Client.from_config`, `.from_hash` | Construct a client from string- or symbol-keyed configuration. | [`client.rb`](../lib/assinafy/client.rb) |
| `Client#faraday_connection` | Return the configured Faraday connection for advanced integration. | [`client.rb`](../lib/assinafy/client.rb) |
| `Client#upload_and_request_signatures` | Upload, optionally wait, create signers, and create a virtual assignment. | [`client.rb`](../lib/assinafy/client.rb) |
| `Client#auth`, `#oauth`, `#accounts`, `#users`, `#documents`, `#contracts`, `#signers`, `#signer_documents`, `#assignments`, `#envelopes`, `#webhooks`, `#templates`, `#fields`, `#tags`, `#webhook_verifier` | Return the client's resource and helper instances. | [`client.rb`](../lib/assinafy/client.rb) |
| `Assinafy::Configuration.new`, `.from_hash` | Build configuration directly or from string/symbol keys. | [`configuration.rb`](../lib/assinafy/configuration.rb) |
| `Configuration#auth_headers` | Return the selected API-key, bearer, or empty authentication header set. | [`configuration.rb`](../lib/assinafy/configuration.rb) |
| Configuration readers/writers: `api_key`, `token`, `account_id`, `base_url`, `webhook_secret`, `timeout`, `logger` | Read or update configuration values; `base_url=` and `timeout=` validate like the constructor. Construct a new client to apply changes. | [`configuration.rb`](../lib/assinafy/configuration.rb) |
| `DocumentResource#activities_page` | Read activities with pagination metadata; `#activities` retains its Array return. | [`document_resource.rb`](../lib/assinafy/resources/document_resource.rb) |
| `DocumentResource#get` | Alias for `#details`. | [`document_resource.rb`](../lib/assinafy/resources/document_resource.rb) |
| `DocumentResource#wait_until_ready` | Poll document details until processing succeeds, fails, or times out. | [`document_resource.rb`](../lib/assinafy/resources/document_resource.rb) |
| `DocumentResource#fully_signed?`, `#signing_progress` | Derive completion state from document assignment data. | [`document_resource.rb`](../lib/assinafy/resources/document_resource.rb) |
| `SignerResource#validate_create!` | Validate and normalize a signer-create body without a network request. | [`signer_resource.rb`](../lib/assinafy/resources/signer_resource.rb) |
| `SignerResource#find_by_email` | Page through a successful search and return a case-insensitive match or `nil`. | [`signer_resource.rb`](../lib/assinafy/resources/signer_resource.rb) |
| `SignerDocumentResource#document` | Alias for `#current`. | [`signer_document_resource.rb`](../lib/assinafy/resources/signer_document_resource.rb) |
| `SignerDocumentResource#list_as_workspace`, `#search_as_workspace` | List/search a signer's documents with workspace credentials; `#list`/`#search` require the signer access code and send only it. | [`signer_document_resource.rb`](../lib/assinafy/resources/signer_document_resource.rb) |
| `AuthResource#api_key` | Alias for `#get_api_key`. | [`auth_resource.rb`](../lib/assinafy/resources/auth_resource.rb) |
| `WebhookResource#update` | Alias for `#register` (acts on the oldest endpoint). | [`webhook_resource.rb`](../lib/assinafy/resources/webhook_resource.rb) |
| `AssignmentResource.build_payload` | Validate and normalize virtual or collect assignment bodies locally. | [`assignment_resource.rb`](../lib/assinafy/resources/assignment_resource.rb) |
| `WebhookVerifier.new`, `#verify_delivery` | Verify a Standard Webhooks delivery (`webhook-id`, `webhook-timestamp`, `webhook-signature`) with the endpoint's `whsec_` secret, rejecting timestamps outside the tolerance (default 300 seconds). |
| `WebhookVerifier#verify` | Verify a hex HMAC-SHA256 signature added by the receiver's own gateway. |
| `WebhookVerifier::SECRET_PREFIX`, `::DEFAULT_TOLERANCE` | The `whsec_` secret prefix and the default 300-second timestamp tolerance. | [`webhook_verifier.rb`](../lib/assinafy/support/webhook_verifier.rb) |
| `WebhookVerifier#extract_event`, `#event_type`, `#event_payload`, `#event_object`, `#event_subject`, `#event_data` | Parse and access webhook envelope fields; `event_data` is retained as a compatibility helper. | [`webhook_verifier.rb`](../lib/assinafy/support/webhook_verifier.rb) |
| `Assinafy::Error.new`, `#context` | Construct/read the SDK base error and its structured context. | [`errors.rb`](../lib/assinafy/errors.rb) |
| `Assinafy::ApiError.new`, `.from_response`, `#status_code`, `#response_data`, `#error_name`, `#error_code`, `#rate_limit`, `#retry_after` | Construct/read an API response error, including its rate-limit headers. | [`errors.rb`](../lib/assinafy/errors.rb) |
| `Assinafy::ValidationError.new`, `#errors`; `Assinafy::NetworkError` | Represent caller-side validation and transport failures. | [`errors.rb`](../lib/assinafy/errors.rb) |
| `Assinafy::OAuthError.new`, `.from_response`, `#error`, `#error_description` | Represent an OAuth endpoint failure; subclasses `ApiError`, so existing rescue clauses keep working. | [`errors.rb`](../lib/assinafy/errors.rb) |
| `Assinafy::OAuth.generate_code_verifier`, `.code_challenge`, `.generate_state`, `.normalize_scope`, `.validate_code_verifier!`, `.authorization_url` | Build the PKCE pair, CSRF state, and authorization URL for the browser half of the OAuth flow. No network request. | [`oauth.rb`](../lib/assinafy/oauth.rb) |
| `Assinafy::OAuth::AUTHORIZATION_SERVER`, `::AUTHORIZATION_SERVER_METADATA_URL`, `::AUTHORIZATION_ENDPOINT`, `::CODE_CHALLENGE_METHOD`, `::SCOPES` | Published authorization-server endpoints and scopes. | [`oauth.rb`](../lib/assinafy/oauth.rb) |
| `AssignmentResource::VERIFICATION_METHODS`, `::NOTIFICATION_METHODS` | The signer verification (`Email`, `Whatsapp`, `DigitalCertificate`, `IdDocumentFaceMatchBasic`) and notification (`Email`, `Whatsapp`) enums, validated locally by `build_payload`. | [`assignment_resource.rb`](../lib/assinafy/resources/assignment_resource.rb) |
| `Assinafy::Utils.handle_assinafy_response`, `.clean_params`, `.query_params`, `.body_params`, `.require_email`, `.require_expiration`, `.require_credit_ceiling`, `.require_credit_ceiling` | Internal public helpers used by resources for envelope and parameter normalization; applications should prefer resource methods. | [`utils.rb`](../lib/assinafy/utils.rb) |
| `Assinafy::NullLogger#debug`, `#info`, `#warn`, `#error`, `#fatal`, `#unknown` | Internal no-op logger methods used when no logger is configured. | [`null_logger.rb`](../lib/assinafy/null_logger.rb) |
| `Assinafy::VERSION` | Published SDK version constant. | [`version.rb`](../lib/assinafy/version.rb) |
| `Assinafy::USER_AGENT` | Version-derived `Assinafy-Ruby-SDK/v[VERSION]` request identifier. | [`version.rb`](../lib/assinafy/version.rb) |

## Request and response examples

The resource methods linked above include request and response examples in their YARD documentation.
The schema catalog below describes the published response objects and their nested properties.

## Schema catalog

All 62 published schemas are listed below. `*` marks required properties. Nested fields are listed with dot notation; links identify reusable schemas. Examples use placeholder contacts.

### Account

A workspace account (organization).

| Property | Type | Description |
| --- | --- | --- |
| `resource` | string |  Example: `"account"`. |
| `id` | string |  Example: `"6401df46d6a6b0c692d9ec49"`. |
| `name` | string |  Example: `"Acme Inc."`. |
| `primary_color` | string or null |  Example: `"aabbcc"`. |
| `secondary_color` | string or null |  Example: `"112233"`. |
| `notification_sender_type` | string (`"User"`, `"Account"`) |  Example: `"User"`. |
| `roles` | Array<string> |  Example: `["owner"]`. |
| `is_delete_allowed` | boolean |  Example: `true`. |
| `limits` | object { `webhook_endpoints`: integer } | Limits of the workspace's current plan. Returned only by `GET /v1/accounts/{accountId}`, not in account lists. More keys may be added. |
| `limits.webhook_endpoints` | integer | How many webhook endpoints the workspace can have: `1`, or `3` with the Multiple Webhooks feature. Creating one past the limit returns `403`. Example: `1`. |
| `signing_features` | object { `DigitalCertificate*`: boolean; `VerificationIdDocumentFaceMatchBasic*`: boolean; `WhatsappNotification*`: boolean; `VerificationBypass*`: boolean; `Embed*`: boolean } | Only with `?expand=signing_features` on `GET /v1/accounts/{accountId}`: which signing features the workspace's subscription includes now (its plan's and any granted to it), so a client offers only the identity checks and notices it can use. `DigitalCertificate` and `VerificationIdDocumentFaceMatchBasic` gate the `DigitalCertificate` and `IdDocumentFaceMatchBasic` verification methods, `WhatsappNotification` the `Whatsapp` notification method (and so the `Whatsapp` verification method), and `VerificationBypass` the `Bypass` verification method. `false` means creating an assignment, or a document from a template, with that method (or estimating its cost) answers `403`. `Embed` gates embedded signing: with `false`, the embed origins endpoints, `"embedded": true` on a signer and minting an embed session answer `403` with code `PlanRestricted`. `true` is not a promise: credits, the assignment's own rules (a `DigitalCertificate` signer needs a `virtual` assignment) and a change of plan still apply. Requires the `account:read` OAuth scope. |
| `signing_features.DigitalCertificate` * | boolean | Signing with the signer's own ICP-Brasil certificate. Example: `true`. |
| `signing_features.VerificationIdDocumentFaceMatchBasic` * | boolean | Identity check by ID document and face match. Example: `false`. |
| `signing_features.WhatsappNotification` * | boolean | Sending signature requests by WhatsApp. Example: `true`. |
| `signing_features.VerificationBypass` * | boolean | Signing without a verification code (the `Bypass` verification method). Example: `false`. |
| `signing_features.Embed` * | boolean | Embedded signing: the signing screen inside your own app (see **Embedded Signing Guide**). Example: `false`. |
| `created_at` | string (format: date-time) |  Example: `"2026-06-03T03:54:16Z"`. |

### AccountTheme

An account's branding theme.

| Property | Type | Description |
| --- | --- | --- |
| `account_name` | string |  Example: `"Account Name"`. |
| `primary_color` | string | Button background: hex color without leading `#`. The platform default when the account set none. Example: `"aabbcc"`. |
| `secondary_color` | string | Button text: hex color without leading `#`. The platform default when the account set none. Example: `"ffffff"`. |
| `logo` | string or null | Absolute URL of the logo for the caller: `/v1/accounts/{accountId}/logo` for workspace members, `/v1/sign/logo` (append `signer-access-code`) for signers. `null` when the account has no logo. Example: `"https://api.assinafy.com.br/v1/accounts/1a/logo"`. |

### AccountUsage

The workspace's plan and what is left of it.

| Property | Type | Description |
| --- | --- | --- |
| `plan` | string or null | The plan's name. `null` when the subscription has no plan or its plan was retired. Example: `"Pro"`. |
| `documents_renewal_date` | string or null (format: date) | When the document allowance next renews. On a custom contract, the next boundary of the contract's billing day. `null` while the subscription awaits its first payment, or on a contract with no billing day. Example: `"2026-12-01"`. |
| `balances` | object { `documents`: [`Balance`](#balance); `credits`: [`Balance`](#balance) } | Document and credit balances, as in **Get current subscription**. |
| `balances.documents` | [`Balance`](#balance) |  |
| `balances.credits` | [`Balance`](#balance) |  |

### ApiKey



| Property | Type | Description |
| --- | --- | --- |
| `api_key` | string or null |  Example: `"mIpe_zdJfKUpMK9Va3XuYgzPXMxz49fIaRCWXseVkpVAX608A9j3i_D67qU5qW3M"`. |

### Assignment

A request for signers to sign a document.

| Property | Type | Description |
| --- | --- | --- |
| `resource` | string |  Example: `"assignment"`. |
| `id` | string |  Example: `"615606ef81d199996981dbce"`. |
| `document_id` | string or null | The document this assignment belongs to. `null` only if the document was deleted. Example: `"615601fab04c0a3147bb1246"`. |
| `created_at` | string (format: date-time) |  Example: `"2026-06-03T03:54:16Z"`. |
| `sender_email` | string or null (format: email) | Email of the user who sent the document; null once that user has deleted their account. Example: `"signer@example.com"`. |
| `method` | string (`"virtual"`, `"collect"`) |  Example: `"virtual"`. |
| `expires_at` | string or null (format: date-time) |  Example: `null`. |
| `message` | string or null |  |
| `signers` | Array<[`AssignmentSigner`](#assignmentsigner)> |  |
| `copy_receivers` | Array<object> |  |
| `items` | Array<[`AssignmentItem`](#assignmentitem)> |  |
| `summary` | [`AssignmentSummary`](#assignmentsummary) |  |
| `signing_urls` | Array<[`SigningUrl`](#signingurl)> |  |

### AssignmentItem



| Property | Type | Description |
| --- | --- | --- |
| `id` | string |  |
| `page` | [`DocumentPage`](#documentpage) or null |  |
| `signer` | object | Signer responsible for this item. |
| `field` | object or null | Field definition associated with the item. |
| `display_settings` | any | Rendering metadata for the item. Collect items use the DisplaySettings schema; virtual and legacy items may return an empty or non-object value. |
| `value` | any | Captured value when completed; `null` until then. |
| `completed` | boolean |  |

### AssignmentSigner

A signer within an assignment: the base Signer plus per-assignment verification/notification details.

| Property | Type | Description |
| --- | --- | --- |
| `resource` | string | Present in single-resource responses. Example: `"signer"`. |
| `id` | string |  Example: `"62d6ee35c7741ca4006b9e11"`. |
| `full_name` | string |  Example: `"John Signer"`. |
| `email` | string or null (format: email) |  Example: `"signer@example.com"`. |
| `whatsapp_phone_number` | string or null | E.164 format; normalized on save. Example: `"+5548999990000"`. |
| `government_id` | string or null | Signer's normalized CPF (11 digits) or CNPJ (14 characters; may be alphanumeric). Example: `"39053344705"`. |
| `has_accepted_terms` | boolean |  Example: `false`. |
| `verification_method` | string or null |  Example: `"Email"`. |
| `notification_methods` | array or null |  Example: `["Email"]`. |
| `step` | integer or null | Sequential signing step (defaults to 1). Example: `1`. |
| `notified` | boolean or null |  |
| `identity_verification_status` | string or null (`"Pending"`, `"InReview"`, `"Approved"`, `"Declined"`, `"Expired"`, `"Abandoned"`) | Latest identity-document verification status; `InReview` means the account must decide it before the document can be certificated. Example: `"InReview"`. |
| `completed` | boolean or null | Only present in account-owner contexts. |
| `notification_history` | array or null | Per-channel delivery history for this signer (email + WhatsApp), most-recent send order. |

### AssignmentSummary



| Property | Type | Description |
| --- | --- | --- |
| `signer_count` | integer |  |
| `completed_count` | integer |  |
| `signers` | Array<object> |  |

### AuthAccount



| Property | Type | Description |
| --- | --- | --- |
| `id` | string |  Example: `"6401df46d6a6b0c692d9ec49"`. |
| `name` | string |  Example: `"JS"`. |
| `roles` | Array<string> |  Example: `["owner"]`. |
| `is_delete_allowed` | boolean |  Example: `true`. |
| `created_at` | string (format: date-time) |  Example: `"2023-03-03T11:51:34Z"`. |

### AuthSession

A JWT access token plus the authenticated user and the accounts they belong to.

| Property | Type | Description |
| --- | --- | --- |
| `access_token` | string |  Example: `"eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9..."`. |
| `user` | [`AuthUser`](#authuser) |  |
| `accounts` | Array<[`AuthAccount`](#authaccount)> |  |

### AuthUser



| Property | Type | Description |
| --- | --- | --- |
| `id` | string |  Example: `"bgjazeo5r9v2lq7l36dx48np"`. |
| `name` | string |  Example: `"John Smith"`. |
| `email` | string (format: email) |  Example: `"signer@example.com"`. |
| `telephone` | string or null |  Example: `"17989206641"`. |
| `government_id` | string or null |  Example: `"15774136604"`. |
| `is_email_verified` | boolean |  Example: `false`. |
| `has_accepted_terms` | boolean |  Example: `true`. |
| `created_at` | string (format: date-time) |  Example: `"2023-03-03T11:51:34Z"`. |
| `to_be_deleted_at` | string or null (format: date-time) |  Example: `null`. |

### Balance

A document or credit balance for the current billing cycle.

| Property | Type | Description |
| --- | --- | --- |
| `balance` | number or null | Remaining quantity; null for unlimited. Example: `100`. |
| `limit` | number or null | Allowance per cycle/pool; null when not cycle-limited or unlimited. Example: `100`. |
| `spent` | number | Quantity consumed in the current cycle. Example: `0`. |

### CostEstimate

Cost breakdown for an assignment plus current account balances. `credits` is the sum of `breakdown` (notifications, digital-certificate signatures and identity checks). `total_credits` is what the send will take from the credit balance: `credits`, plus `extra_document_cost` when `needs_extra_document` is true. The extra document is not a `breakdown` line.

| Property | Type | Description |
| --- | --- | --- |
| `documents` * | integer | Documents consumed: 1, for an assignment as for an envelope, whatever its documents. Example: `1`. |
| `credits` * | number | Sum of the `breakdown` costs: notifications, digital-certificate signatures and identity checks. Does not include the extra document. Example: `0.9`. |
| `needs_extra_document` * | boolean | True when the plan's document allowance is exhausted and an extra document will be charged from credits. Example: `true`. |
| `extra_document_cost` * | number | Credits for one extra document. Charged only when `needs_extra_document` is true. Example: `1`. |
| `total_credits` * | number | Credits the send will consume: `credits`, plus `extra_document_cost` when `needs_extra_document` is true. Example: `1.9`. |
| `breakdown` * | Array<[`CostEstimateBreakdownItem`](#costestimatebreakdownitem)> |  |
| `document_balance` * | number or null | Documents left in the plan. `null` when the account's documents are not limited. Example: `0`. |
| `credit_balance` * | number or null | Credits available. `null` when the account's credits are not limited. Example: `10`. |
| `has_sufficient_resources` * | boolean | Whether creating it would pass its balance checks now: the checks creation itself makes, so a contract that allows overage passes with a low `document_balance` or `credit_balance`. Example: `true`. |
| `blocking_reason` * | string or null (`"PendingPayment"`, `"InsufficientDocuments"`, `"InsufficientCredits"`) |  Example: `null`. |
| `message` * | string or null |  |

### CostEstimateBreakdownItem



| Property | Type | Description |
| --- | --- | --- |
| `code` | string |  Example: `"NotificationWhatsapp"`. |
| `name` | string |  Example: `"Whatsapp Notification"`. |
| `cost` | number |  Example: `0.9`. |
| `quantity` | integer |  Example: `2`. |
| `unit_cost` | number |  Example: `0.45`. |

### DisplaySettings

A field placement rectangle on a document page. Geometry values are pixels in Assinafy's 150-DPI page image, measured from the upper-left corner. Clients must keep the rectangle within the selected page's width and height; the API does not clamp out-of-bounds values.

| Property | Type | Description |
| --- | --- | --- |
| `left` * | number (format: float) (min: 0) | Horizontal distance from the page's left edge, in page-image pixels. Example: `69`. |
| `top` * | number (format: float) (min: 0) | Vertical distance from the page's top edge, in page-image pixels. Example: `282`. |
| `width` * | number (format: float) | Width of the placement rectangle, in page-image pixels. Example: `421`. |
| `height` * | number (format: float) | Height of the placement rectangle, in page-image pixels. Example: `45.86`. |
| `fontFamily` | string | Font-family presentation metadata. Example: `"Arial"`. |
| `fontSize` * | number (format: float) | Font size in the 150-DPI page-image coordinate system. Example: `22`. |
| `backgroundColor` | string | CSS-compatible background-color presentation metadata. Example: `"#D5EBFF"`. |

### Document

A document and its current lifecycle state.

| Property | Type | Description |
| --- | --- | --- |
| `resource` | string | Present in single-resource responses. Example: `"document"`. |
| `id` | string |  Example: `"615601fab04c0a3147bb1246"`. |
| `account_id` | string |  Example: `"d199996981dbd199996981db"`. |
| `template_id` | string or null |  Example: `null`. |
| `name` | string |  Example: `"document.pdf"`. |
| `status` | string | Status code — see GET /v1/documents/statuses. Example: `"metadata_ready"`. |
| `artifacts` | object | Artifact download URLs keyed by name. Always `original`, plus `thumbnail` once one exists. A certificated document also carries `certificated`, `certificate-page` and `bundle`, and `pades` when it was signed with a digital certificate — the PAdES version holds the signers' ICP-Brasil signatures, which certification flattens out of the certificated PDF. Example: `{"original":"https://api.assinafy.com.br/v1/documents/doc1/download/original"}`. |
| `is_closed` | boolean |  Example: `false`. |
| `signing_url` | string |  Example: `"https://api.assinafy.com.br/v1/sign/doc1"`. |
| `verification_code` | string or null | The code printed on the certificate page. Anyone can check it with `GET /v1/documents/{verification_code}/verify` or on `verification_url`. `null` until the document is `certificated`, and on documents certificated before verification codes existed. Example: `"a3f1c9e07b2d4e8f9a6c5b1d0e7f3a2c9b8d4e6f"`. |
| `verification_url` | string or null (format: uri) | The public verification page for this document. `null` until the document is `certificated`. Example: `"https://www.assinafy.com.br/verificador/a3f1c9e07b2d4e8f9a6c5b1d0e7f3a2c9b8d4e6f"`. |
| `decline_reason` | string or null |  Example: `null`. |
| `declined_by` | [`Signer`](#signer) or null |  |
| `tags` | Array<object { `id`: string; `name`: string; `color`: string or null }> |  |
| `tags[].id` | string |  |
| `tags[].name` | string |  |
| `tags[].color` | string or null | 6-char hex without leading #. Example: `"ff8800"`. |
| `assignment` | [`Assignment`](#assignment) or null | The document's assignment, or `null` before one is created. The server decides when it is included, whatever `expand` the request sends: the document list, `GET /v1/documents/{documentId}`, the signer's document list and document creation from a template always include it; `/documents/search` and the upload response never do. Only the rename response follows `?expand=assignment`. |
| `pages` | Array<[`DocumentPage`](#documentpage)> | The document's pages. Included on the same responses as `assignment`, and also on the upload response. |
| `envelope_id` | string or null | Only on `GET /v1/documents/{documentId}?expand=envelope_id` read by the workspace, not in document lists or webhooks, so their payloads keep their shape: the envelope this document is in, or `null` for a document sent on its own, taken out of its envelope, or whose envelope was deleted. Example: `null`. |
| `envelope` | object { `id*`: string; `name*`: string } | Only on `GET /v1/documents/{documentId}?expand=envelope` read by the workspace and `GET /v1/sign?expand=envelope` or `GET /v1/signers/{signerId}/document?expand=envelope` read with the signer's code, not in document lists or webhooks: the envelope this document is in, or `null` for a document sent on its own, taken out of its envelope, or whose envelope was deleted. The signer's reads name the envelope their code belongs to even when the code's own document was taken out, since the code still reaches the rest. |
| `envelope.id` * | string |  Example: `"fe1c140cb49b79f940aab95fddd"`. |
| `envelope.name` * | string |  Example: `"Contrato de prestação de serviços"`. |
| `has_contract` | boolean | Only on `GET /v1/documents/{documentId}` read by the workspace, while the environment has contract tracking on: not with a signer's access code, not in document lists or webhooks, and left out when the lookup fails, so a missing key means unknown. Whether `GET /v1/accounts/{accountId}/documents/{documentId}/contract` answers with contract terms, the document's own or those of a contract it amends whose document still exists, so a page can lay out the contract section before reading it. Example: `true`. |
| `created_at` | string (format: date-time) |  Example: `"2026-06-03T03:54:16Z"`. |
| `updated_at` | string (format: date-time) |  Example: `"2026-06-03T03:54:16Z"`. |

### DocumentActivity

A document activity event.

| Property | Type | Description |
| --- | --- | --- |
| `id` | integer |  Example: `4`. |
| `event` | string | Event type code. Example: `"assignment_created"`. |
| `message` | string |  Example: `"Assignment created by John Smith."`. |
| `payload` | object or array or null | `[]` for the events that record nothing (`document_uploaded`, `document_metadata_ready`, `document_prepared`). Otherwise an event-specific snapshot taken when the event happened, with the same keys as the webhook of that event (see **Webhook Payloads**). The common ones: `user_name` (`assignment_created`, `user_rejected_document`); `signer_full_name` (every `signer_*` event and `signature_requested`); `signer_email`, `signer_whatsapp_phone_number` and `notification_method` (`signature_requested`); `reviewer_name` (identity review decisions); `error_message` (`document_processing_failed`). `message` already carries the actor's name, translated, so clients can show it as is. A `*_at` key inside the payload is returned as an ISO 8601 string here, as in every API response, but as a Unix integer in webhook bodies. |
| `origin` | object { `ip`: string or null; `user-agent`: string } | Request origin when available. |
| `origin.ip` | string or null | `null` when the request carried no client address. Example: `"172.19.0.1"`. |
| `origin.user-agent` | string |  |
| `created_at` | string (format: date-time) |  Example: `"2022-07-19T19:28:13Z"`. |

### DocumentContract

The contract terms tracked on a document. Every key below is always present, `null` when it holds no value, except `resource`, `document` and `amendments`, which depend on the response.

| Property | Type | Description |
| --- | --- | --- |
| `resource` | string | On a response that is this contract alone; list items carry none. Example: `"document_contract"`. |
| `document_id` * | string |  Example: `"66b2f0e1c3a4d5e6f7a8b9c0"`. |
| `status` * | string (`"draft"`, `"active"`, `"expired"`, `"terminated"`) |  Example: `"active"`. |
| `counterparty_name` * | string or null |  Example: `"Acme Ltda"`. |
| `counterparty_taxpayer_id` * | string or null | CPF or CNPJ, digits only. Example: `"11222333000181"`. |
| `value` * | number or null | Two decimal places at most. Example: `120000.5`. |
| `currency` * | string or null | ISO 4217 code; `BRL` when a value is sent without one. Example: `"BRL"`. |
| `start_date` * | string or null (format: date) |  Example: `"2026-11-01"`. |
| `end_date` * | string or null (format: date) |  Example: `"2027-10-31"`. |
| `auto_renew` * | boolean |  Example: `true`. |
| `renewal_term_months` * | integer or null |  Example: `12`. |
| `notice_period_days` * | integer or null |  Example: `30`. |
| `term` * | integer | Steps on every renewal, starting at 1. Example: `1`. |
| `owner_id` * | string or null | ID of the workspace member who owns the contract. When the owner is no longer a member of the workspace (removed, left, or deleted with their account), the hourly run hands the contract to the first owner who is still an active member, or leaves it without one; an inactive member stays the owner. The contract's e-mails (renewal notice, expiring, expired, renewed) go to the first of the owner and the document's creator who is an active member, as that member's notification preferences allow. Example: `"d6zqpbyog2v3xvxerwn8la94"`. |
| `metadata` * | object or null; additional values: string | Up to 50 keys of your own, each holding text of at most 500 characters; `null` when there are none. Values come back exactly as sent. A key ending in `_at`, or `stuck_since`, cannot hold a number. Example: `{"crm_stage":"won"}`. |
| `external_references` * | Array<object { `system*`: string; `id*`: string }> | IDs outside systems use for this contract, ordered by system and id; `[]` when there are none. |
| `external_references[].system` * | string |  Example: `"hubspot"`. |
| `external_references[].id` * | string |  Example: `"98765"`. |
| `document` | [`Document`](#document) | Only with `expand=document`: the document the terms are tracked on. |
| `amendments` | Array<[`DocumentContractAmendment`](#documentcontractamendment)> | Only on the contract read and the related read (`GET …/contract`, `GET …/contract/related`), never on the list or on the answer to a write, renewal or termination: the documents that amend, renew or terminate this contract, the applied ones first by `number`, then the pending ones. |
| `created_at` * | string (format: date-time) |  Example: `"2026-10-23T12:00:00Z"`. |
| `updated_at` * | string (format: date-time) |  Example: `"2026-10-23T12:00:00Z"`. |

### DocumentContractAmendment

A document that amends, renews or terminates a contract: its link and the terms it changes. The parent's terms take the delta once this document is certificated; until then the parent is untouched. Every key below is always present, `null` when it holds no value, except `resource`.

| Property | Type | Description |
| --- | --- | --- |
| `resource` | string | On a response that is this amendment alone; the entries of a contract's `amendments` carry none. Example: `"document_contract_amendment"`. |
| `document_id` * | string | This document, the instrument. Example: `"7c3d1e2f4a5b6c7d8e9f0a1b"`. |
| `document_name` * | string | This document's name. Example: `"Aditivo 1 - Contrato de prestação de serviços.pdf"`. |
| `parent_document_id` * | string | The contract document whose terms change. Example: `"66b2f0e1c3a4d5e6f7a8b9c0"`. |
| `relation_type` * | string (`"amendment"`, `"renewal"`, `"termination"`) |  Example: `"amendment"`. |
| `number` * | integer or null | Position among the parent's applied amendments by signing date; `null` while pending. Example: `1`. |
| `status` * | string (`"pending"`, `"applied"`) | `applied` once the delta moved the parent's terms. Example: `"pending"`. |
| `document_status` * | string | This document's own status, so a declined, cancelled or expired instrument shows as such. An instrument applies only while its document is `certificated`: one whose document reads `failed` after it was signed waits, with no `apply_error`, until it is certificated again, and then applies in its place in the signing order. Example: `"pending_signature"`. |
| `apply_error` * | string or null | Why a signed instrument has not applied yet, retried every hour: the workspace's plan does not include contract tracking (it applies on the first run after the plan returns), the parent would not take the delta, an instrument signed before this one has not applied yet, one signed after it has already applied (this one then stays blocked: unlink it, and record what it still changes on a new instrument), or an unexpected failure. |
| `currency` * | string or null | The currency of the amounts in `terms` and `changes`. Once applied, the contract's currency at that moment, kept whatever the contract moves to later. While pending (and for an instrument applied before this was kept), the one this instrument moves the contract to, otherwise the contract's. `null` when neither has one. Example: `"BRL"`. |
| `terms` * | object or null | The delta: only the terms this instrument changes; `null` when it changes none (a termination on the day it is signed). Example: `{"value":130000,"end_date":"2028-06-30"}`. |
| `changes` * | object or null | Every parent field the roll-up moves, as `{from, to}`: a preview while pending, the record once applied; `null` when it moves none. Example: `{"value":{"from":120000.5,"to":130000},"end_date":{"from":"2027-10-31","to":"2028-06-30"},"term":{"from":1,"to":2}}`. |
| `applied_at` * | string or null (format: date-time) |  |
| `created_at` * | string (format: date-time) |  Example: `"2026-10-23T12:00:00Z"`. |
| `updated_at` * | string (format: date-time) |  Example: `"2026-10-23T12:00:00Z"`. |

### DocumentContractInput

Every attribute is optional and only the ones sent change. `null` clears an attribute, except `auto_renew` (back to `false`) and `currency` (back to `BRL` while a `value` is set); `status` does not accept `null`. A changed `end_date` starts a new `term`.

| Property | Type | Description |
| --- | --- | --- |
| `status` | string (`"draft"`, `"active"`, `"expired"`, `"terminated"`) | On creation any status, so a contract that ended before it was tracked is registered as it ended: `expired` needs an `end_date` in the past, `terminated` its `end_date`; neither is walked by the lifecycle. Afterwards only `draft` or `active` (a contract in force never goes back to `draft`): `expired` and `terminated` are set by the lifecycle and the terminate endpoint; a closed contract is reopened by renewing it. |
| `counterparty_name` | string or null (max length: 255) | Emoji are kept; other characters outside the 3-byte range are dropped. |
| `counterparty_taxpayer_id` | string or null | A valid CPF or CNPJ, formatted or not. |
| `value` | number or null (min: 0) (max: 9999999999999.99) | Two decimal places at most. |
| `currency` | string or null | Three letters, such as `BRL` or `USD`, stored in capitals; `BRL` when a `value` is set without one. Example: `"BRL"`. |
| `start_date` | string or null (format: date) | `YYYY-MM-DD`, from the year 1000. |
| `end_date` | string or null (format: date) | `YYYY-MM-DD`, on or after `start_date`. |
| `auto_renew` | boolean | Whether the hourly run starts the next term the day after `end_date`, by `renewal_term_months`, instead of expiring the contract. |
| `renewal_term_months` | integer or null (min: 1) (max: 600) | How far a renewal by the term moves `end_date`; 12 when unset. |
| `notice_period_days` | integer or null (min: 0) (max: 3650) | Days before `end_date` the notice period starts (`document_contract_renewal_notice`); none when unset. |
| `owner_id` | string or null | An active member of this workspace. |
| `metadata` | object or null; additional values: string (max length: 500) | Your own fields: up to 50 keys of 1 to 40 letters, digits, `_`, `-` or `.`, each holding plain text of at most 500 characters; no number under a key ending in `_at`, or `stuck_since`. |
| `external_references` | array or null (max items: 20) | Replaces the whole list; `[]` or `null` clears it. Two items whose `system` and `id` compare equal case aside are one reference (the first sent is kept); a pair the database takes for one beyond that (accents, `ß` and `ss`) answers `400`. |
| `parent_document_id` | string or null | Links the document as an amendment of this contract document, or of any document in its family (resolved to the root); `null` unlinks a pending amendment. With it, the other attributes are the terms the instrument changes, not terms of its own; on a pending amendment a `null` value drops that term from the delta rather than clearing it on the parent. |
| `relation_type` | string (`"amendment"`, `"renewal"`, `"termination"`) | Required on the first link. `amendment` may change `value`, `currency`, `start_date` (effective from, display only), `end_date`, `auto_renew`, `renewal_term_months`, `notice_period_days`, `counterparty_name`, `counterparty_taxpayer_id` and `metadata`; `renewal` only `end_date` and `value`; `termination` only `end_date` (the effective date). |
| `updated_at` | string (format: date-time) | Optional precondition: the `updated_at` the client read the contract (or this document's amendment link) with, as the API returned it. If the contract or link changed since, nothing is written and the answer is `409` with `code: ContractChanged`. Not sent, or `null`: the write applies whatever changed meanwhile (last write wins). Compared to the second; a fraction of a second, as a JavaScript date prints it, is read and ignored. New terms and a first link have nothing to have read, so sending one answers `409`; on a pending amendment, send the link's own `updated_at` (the GET on that document). Example: `"2026-10-23T12:00:00Z"`. |

### DocumentEnvelope

Documents sent together to the same signers. Each document keeps its own assignment, status, certificate and downloads.

| Property | Type | Description |
| --- | --- | --- |
| `resource` | string | Present in single-resource responses. Example: `"envelope"`. |
| `id` * | string |  Example: `"1a2f3c4d5e6f708192a3b4c5d6e"`. |
| `name` * | string |  Example: `"Contrato de prestação de serviços"`. |
| `message` * | string or null |  Example: `"Segue o contrato e seus anexos."`. |
| `documents` * | Array<object { `id*`: string; `position*`: integer (min: 1); `name*`: string; `status*`: string; `artifacts*`: object; additional values: string; `signers*`: Array<object { `id*`: string; `full_name*`: string; `email*`: string or null; `whatsapp_phone_number*`: string or null; `completed*`: boolean; `signed_at*`: string or null (format: date-time) }> }> | The envelope's documents, in the order it lists them. |
| `documents[].id` * | string |  Example: `"615601fab04c0a3147bb1246"`. |
| `documents[].position` * | integer (min: 1) | The document's place in the envelope's order, from 1. Example: `1`. |
| `documents[].name` * | string |  Example: `"contrato.pdf"`. |
| `documents[].status` * | string | Status code — see GET /v1/documents/statuses. Example: `"pending_signature"`. |
| `documents[].artifacts` * | object; additional values: string | The document's files, as its own read (`GET /v1/documents/{documentId}`) gives them: always `original`, plus `thumbnail` once one exists, and for a certificated document `certificated`, `certificate-page`, `bundle` and, when signed with a digital certificate, `pades`. In the envelope list (`GET /v1/accounts/{accountId}/envelopes`) only `thumbnail`, given without checking that it exists: its URL answers `404` until the thumbnail is generated. Example: `{"original":"https://api.assinafy.com.br/v1/documents/615601fab04c0a3147bb1246/download/original","thumbnail":"https://api.assinafy.com.br/v1/documents/615601fab04c0a3147bb1246/thumbnail"}`. |
| `documents[].signers` * | Array<object { `id*`: string; `full_name*`: string; `email*`: string or null; `whatsapp_phone_number*`: string or null; `completed*`: boolean; `signed_at*`: string or null (format: date-time) }> | The document's signers: a signer appears only on the documents they are on. |
| `documents[].signers[].id` * | string |  Example: `"fa8c140cb49b79f940aab95fddd"`. |
| `documents[].signers[].full_name` * | string |  Example: `"Ana Souza"`. |
| `documents[].signers[].email` * | string or null |  Example: `"signer@example.com"`. |
| `documents[].signers[].whatsapp_phone_number` * | string or null |  Example: `"+5548999990001"`. |
| `documents[].signers[].completed` * | boolean | Whether they have signed this document. Example: `false`. |
| `documents[].signers[].signed_at` * | string or null (format: date-time) | When they signed this document; `null` until they do. Example: `"2026-11-06T14:30:00Z"`. |
| `counts` * | object or null; additional values: integer | How many of its documents are in each status (status code => count); only the statuses present. An envelope has no status of its own. `null` once it lists no document: every one deleted or taken out. Example: `{"certificated":1,"pending_signature":2}`. |
| `signing_urls` * | Array<[`SigningUrl`](#signingurl)> | One entry per signer, as on an assignment (`SigningUrl`): the link of the document their invitation is sent from while it waits for them, else of their first document that still does (the e-mail page asks that document for the invitation again; any of their links opens the whole envelope). |
| `created_at` * | string (format: date-time) |  Example: `"2026-11-04T12:00:00Z"`. |

### DocumentPage



| Property | Type | Description |
| --- | --- | --- |
| `id` | string |  Example: `"615601faf166d6d1d8e7dc30"`. |
| `number` | integer |  Example: `1`. |
| `height` | integer |  Example: `2100`. |
| `width` | integer |  Example: `1275`. |
| `download_url` | string |  Example: `"https://api.assinafy.com.br/v1/documents/doc1/pages/1a/download"`. |

### DocumentStatsRow

One period of the document-funnel KPI series. `period` is `YYYY-MM` (monthly) or `YYYY-MM-DD` (daily); series are zero-filled, no gaps. Signature requests come with two independent breakdowns: the `signature_requests_notification_*` counters split them by the channels the signer was notified on — a signer reached on more than one channel counts once per channel, so these add up to at least `signature_requests` — while the `signature_requests_verification_*` counters split them by how the signer's identity is verified, and since each request has exactly one verification method those four always add up to `signature_requests`.

| Property | Type | Description |
| --- | --- | --- |
| `period` | string | `YYYY-MM` (monthly) or `YYYY-MM-DD` (daily). Example: `"2026-06"`. |
| `documents_uploaded` | integer |  Example: `42`. |
| `documents_sent` | integer |  Example: `37`. |
| `signature_requests` | integer |  Example: `61`. |
| `signature_requests_notification_email` | integer | Requests notified by e-mail. Example: `55`. |
| `signature_requests_notification_whatsapp` | integer | Requests notified by WhatsApp. Example: `18`. |
| `signature_requests_notification_bypass` | integer | Requests with no notification sent (`Bypass`). Example: `3`. |
| `signature_requests_verification_email` | integer | Requests verified by an e-mail token. Example: `48`. |
| `signature_requests_verification_whatsapp` | integer | Requests verified by a WhatsApp token. Example: `6`. |
| `signature_requests_verification_bypass` | integer | Requests signed without token verification (`Bypass`). Example: `3`. |
| `signature_requests_verification_digital_certificate` | integer | Requests signed with the signer's own ICP-Brasil digital certificate. Example: `4`. |
| `signature_requests_viewed` | integer | Signature requests whose document was first viewed during the period. Example: `44`. |
| `signature_requests_completed` | integer | Signature requests completed by individual signers during the period. Example: `52`. |
| `documents_certified` | integer |  Example: `30`. |

### DocumentStatus



| Property | Type | Description |
| --- | --- | --- |
| `code` | string |  Example: `"metadata_ready"`. |
| `deletable` | boolean |  Example: `true`. |

### DocumentVerification

The verification result for a document looked up by signature hash. When not verified, most fields are null and `is_valid` is false.

| Property | Type | Description |
| --- | --- | --- |
| `hash` | string |  Example: `"FE32EDDADE7CBDDCBB934E7402047450B0E59C02"`. |
| `id` | string or null |  Example: `"63ddb172402799bfc991d10d"`. |
| `agreement_code` | string or null | Agreement code printed on the document certificate. Example: `"550E8400-E29B-41D4-A716-446655440000"`. |
| `status` | string or null |  Example: `"certificated"`. |
| `page_count` | string or null |  Example: `"1"`. |
| `signer_count` | string or null |  Example: `"1"`. |
| `completed_count` | integer or null |  Example: `1`. |
| `completed_at` | string or null (format: date-time) | When the last signature was made. Example: `"2023-01-27T19:27:44Z"`. |
| `certificated_at` | string or null (format: date-time) | When certification was first recorded by the document_ready event. Null when no certification event is available, including some historical documents. Example: `"2023-01-27T19:27:45Z"`. |
| `verified_at` | string (format: date-time) | When this check ran (the time of the request). It says nothing about when the document was signed or certified. Example: `"2023-01-27T19:27:46Z"`. |
| `is_valid` | boolean |  Example: `true`. |
| `message` | string | Reason when not valid. Example: `""`. |

### EmbedOrigin

An origin allowed to embed the workspace's signing pages.

| Property | Type | Description |
| --- | --- | --- |
| `id` | string | Embed origin ID. Example: `"6f1c2a9e0b"`. |
| `origin` | string | Exact `scheme://host[:port]`. Example: `"https://app.example.com"`. |
| `created_at` | string (format: date-time) |  Example: `"2026-11-04T12:05:00Z"`. |

### EmbedSession

A single-use embed session for an embedded signer.

| Property | Type | Description |
| --- | --- | --- |
| `url` | string | Load this URL in an iframe within 5 minutes. Opening it spends the token. Example: `"https://app.assinafy.com.br/embed/3f2c9a1e5b7d4c68a0e1f2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f7"`. |
| `expires_at` | string (format: date-time) |  Example: `"2026-11-04T12:05:00Z"`. |

### EmbedSessionExchange

What the embed page gets for a session token.

| Property | Type | Description |
| --- | --- | --- |
| `signer_access_code` | string | The signer's access code, used by the embed page only. |
| `signer_id` | string |  Example: `"6f1c2a9e0b"`. |
| `document_id` | string |  Example: `"5e0b1c2a9f"`. |
| `verification_method` | string |  Example: `"Email"`. |
| `embed_origins` | Array<string> |  Example: `["https://app.example.com"]`. |

### Envelope

Standard success wrapper. Operations add their own `data`.

| Property | Type | Description |
| --- | --- | --- |
| `status` | integer | HTTP status code, mirrored in the body. Example: `200`. |
| `message` | string | Human-readable message; empty on success. Example: `""`. |

### EnvelopeActivity

A document activity of an envelope's trail, naming its document.

| Property | Type | Description |
| --- | --- | --- |
| `id` | integer |  Example: `4`. |
| `event` | string | Event type code. Example: `"assignment_created"`. |
| `message` | string |  Example: `"Assignment created by John Smith."`. |
| `payload` | object or array or null | `[]` for the events that record nothing (`document_uploaded`, `document_metadata_ready`, `document_prepared`). Otherwise an event-specific snapshot taken when the event happened, with the same keys as the webhook of that event (see **Webhook Payloads**). The common ones: `user_name` (`assignment_created`, `user_rejected_document`); `signer_full_name` (every `signer_*` event and `signature_requested`); `signer_email`, `signer_whatsapp_phone_number` and `notification_method` (`signature_requested`); `reviewer_name` (identity review decisions); `error_message` (`document_processing_failed`). `message` already carries the actor's name, translated, so clients can show it as is. A `*_at` key inside the payload is returned as an ISO 8601 string here, as in every API response, but as a Unix integer in webhook bodies. |
| `origin` | object { `ip`: string or null; `user-agent`: string } | Request origin when available. |
| `origin.ip` | string or null | `null` when the request carried no client address. Example: `"172.19.0.1"`. |
| `origin.user-agent` | string |  |
| `created_at` | string (format: date-time) |  Example: `"2022-07-19T19:28:13Z"`. |
| `document_id` | string | The document the activity is about. Example: `"fe1c140cb49b79f940aab95fddd"`. |
| `document_name` | string |  Example: `"Contrato.pdf"`. |

### EnvelopeCreateRequest

An envelope as sent: on creation, and to estimate what creating it would cost.

| Property | Type | Description |
| --- | --- | --- |
| `name` * | string (min length: 1) (max length: 255) | What the invitation calls what is being signed, in place of a document's name. `<` is refused (`400`). Example: `"Contrato de prestação de serviços"`. |
| `message` | string or null | Optional message sent to every signer; their invitation adds the names of the documents they are on. Example: `"Segue o contrato e seus anexos."`. |
| `max_total_credits` | number (min: 0) | Optional ceiling on what this request may spend, as on an assignment: refused with `409` and code `CreditCeilingExceeded`, nothing created or charged, when the envelope's total credits are above it. A value that is not a number of credits, zero or more, answers `400`; numeric text counts, as a form-encoded body sends it. The estimate ignores it. Example: `1.5`. |
| `signers` * | Array<object { `id*`: string (min length: 1); `verification_method`: string (`"Email"`, `"Whatsapp"`, `"DigitalCertificate"`, `"IdDocumentFaceMatchBasic"`); `notification_methods`: Array<string (`"Email"`, `"Whatsapp"`)> (max items: 1); `embedded`: boolean }> (min items: 1) (max items: 20) | Every signer of the envelope, once, by id: up to 20. They all sign at once: an envelope takes no `step`. |
| `signers[].id` * | string (min length: 1) | An existing signer's ID. Example: `"fa8c140cb49b79f940aab95fddd"`. |
| `signers[].verification_method` | string (`"Email"`, `"Whatsapp"`, `"DigitalCertificate"`, `"IdDocumentFaceMatchBasic"`) | As on an assignment. A `DigitalCertificate` signer signs only virtual documents, alone on each, each with their certificate, and is charged on each. An `IdDocumentFaceMatchBasic` signer checks their identity once for the whole envelope, and is charged for it once. Example: `"Email"`. |
| `signers[].notification_methods` | Array<string (`"Email"`, `"Whatsapp"`)> (max items: 1) | As on an assignment: one method, inferred from `verification_method` when left out. Example: `["Email"]`. |
| `signers[].embedded` | boolean | As on an assignment: the signer signs inside your app, through an embed session, on every document of the envelope, the ones added later too. Their `signing_urls` entry has no link (`url` is `null`). An embed session minted on any of their documents still waiting for them lists the documents of the envelope they still have to sign, and the code their invitation carries verifies them there. |
| `documents` * | Array<[`EnvelopeDocumentRequest`](#envelopedocumentrequest)> (min items: 1) (max items: 20) | The documents, in the order the envelope lists them: up to 20. |

### EnvelopeDocumentRequest

A document of an envelope, as sent on creation (`documents[]`) and when added.

| Property | Type | Description |
| --- | --- | --- |
| `id` * | string (min length: 1) | A `metadata_ready` document of the workspace with no assignment. Example: `"615601fab04c0a3147bb1246"`. |
| `method` | string (`"virtual"`, `"collect"`) | As on an assignment: `virtual` (the default), signed on its virtual page, or `collect`, signed on the fields placed in `entries`. |
| `entries` | Array<object { `page_id*`: string; `fields*`: Array<object { `signer_id*`: string; `field_id*`: string; `display_settings*`: [`DisplaySettings`](#displaysettings) }> (min items: 1) }> (min items: 1) | Required for `collect`, as on an assignment: the fields placed on each page of the document. Its signers are the ones on its fields, exactly its `signer_ids`. |
| `entries[].page_id` * | string | A page of the document. |
| `entries[].fields` * | Array<object { `signer_id*`: string; `field_id*`: string; `display_settings*`: [`DisplaySettings`](#displaysettings) }> (min items: 1) |  |
| `entries[].fields[].signer_id` * | string | A signer of the document. |
| `entries[].fields[].field_id` * | string | A field definition of the workspace. |
| `entries[].fields[].display_settings` * | [`DisplaySettings`](#displaysettings) |  |
| `signer_ids` * | Array<string> (min items: 1) | The signers of this document, each listed once: on creation, signers listed in `signers`; when added, signers of the envelope's documents. Example: `["fa8c140cb49b79f940aab95fddd"]`. |
| `expires_at` | string or number or null | This document's expiration, read as on an assignment, at least one hour in the future. Text is read as a date: ISO 8601 is the format to send (a UTC offset in the value is honored, a value without one is read as UTC, and a date alone means 23:59 UTC that day), and text that is a number is Unix time. A number is Unix time in seconds, its fraction dropped. Null, 0, an empty text or leaving it out means no expiration; a value that can't be read as a date answers `400`. Example: `"2026-12-31T23:59:59Z"`. |
| `copy_receiver_ids` | Array<string> | Signer IDs that only receive a copy of this document, as on an assignment. Example: `["cr8c140cb49b79f940aab95fddd"]`. |

### ErrorEnvelope

Standard error wrapper. `status` mirrors the HTTP status code.

| Property | Type | Description |
| --- | --- | --- |
| `status` | integer |  Example: `400`. |
| `message` | string | Human-readable error message. Example: `"Bad request."`. |
| `data` | object or null |  Example: `null`. |
| `code` | string | On the refusals a client can act on: see Reading a refusal. Other refusals have only `message`. Example: `"PlanRestricted"`. |
| `errors` | Array<object { `field*`: string or null; `code*`: string; `message*`: string }> | On a `400` about a field (a model's validation, a missing or an unknown field): one entry per field in error; `message` stays the first entry's. Other `400`s have only `message`. See Reading a refusal. |
| `errors[].field` * | string or null | The field as sent, a dot for a nested one (`address.line1`); `null` when the request as a whole is refused. Example: `"full_name"`. |
| `errors[].code` * | string | `Required`, `UnknownField` or `Invalid`; the contract endpoints have codes of their own. Example: `"Required"`. |
| `errors[].message` * | string | In the platform's language. Example: `"Full Name cannot be blank."`. |

### Field

A reusable field definition.

| Property | Type | Description |
| --- | --- | --- |
| `resource` | string |  Example: `"field"`. |
| `id` | string |  Example: `"6152120297080d55bdd13197"`. |
| `name` | string |  Example: `"Signature"`. |
| `type` | string |  Example: `"signature"`. |
| `regex` | string or null |  |
| `is_pre_defined` | boolean |  |
| `is_active` | boolean |  |
| `is_required` | boolean |  |
| `is_standard` | boolean |  |
| `is_read_only` | boolean |  |
| `is_visible` | boolean |  |

### FieldType

A supported field/validation type.

| Property | Type | Description |
| --- | --- | --- |
| `type` | string |  Example: `"cpf"`. |
| `name` | string |  Example: `"CPF"`. |

### FieldValidation

The result of validating a value against a field definition.

| Property | Type | Description |
| --- | --- | --- |
| `type` | string | The field's validation type. Example: `"cpf"`. |
| `success` | boolean |  Example: `true`. |
| `error_message` | string | Empty when valid. Example: `""`. |

### FieldValidationResult

A per-field result from a multi-field validation.

| Property | Type | Description |
| --- | --- | --- |
| `field_id` | string |  Example: `"63488ffb7adf435aba319787"`. |
| `type` | string |  Example: `"cpf"`. |
| `success` | boolean |  Example: `false`. |
| `error_message` | string |  Example: `"Invalid CPF."`. |

### NotificationHistoryEntry

A single notification delivery record for a signer channel.

| Property | Type | Description |
| --- | --- | --- |
| `event` | string |  Example: `"signature_request"`. |
| `status` | string (`"sent"`, `"delivered"`, `"opened"`, `"failed"`) | Furthest delivery stage reached. `opened` means the email was opened/clicked or the WhatsApp message was read. Example: `"failed"`. |
| `error_code` | string or null (`"MailboxFull"`, `"AddressNotFound"`, `"AddressSuppressed"`, `"ContentRejected"`, `"MarkedAsSpam"`, `"NotOnWhatsapp"`, `"RecipientRestricted"`, `"NotSent"`, `"Unknown"`) | Why the notification failed. Only set when `status` is `failed`. Example: `"MailboxFull"`. |
| `error_message` | string or null | Human-readable, localized explanation of `error_code`. Only set when `status` is `failed`. Example: `"A caixa de entrada do destinatário está cheia. Peça ao signatário para liberar espaço ou use outro e-mail."`. |
| `sent_at` | string or null (format: date-time) |  Example: `"2026-07-07T12:00:00Z"`. |
| `failed_at` | string or null (format: date-time) |  Example: `"2026-07-07T12:05:00Z"`. |

### NotificationPolicy

The workspace's notification rules, set by its owners.

| Property | Type | Description |
| --- | --- | --- |
| `editable` | boolean | Whether the requesting user is an owner and can change the policy. Example: `true`. |
| `owners_receive_all` | boolean | Owners also get the push alerts for every member's documents. Each owner's own preferences still apply. Example: `false`. |
| `events` | [`NotificationPolicyEvents`](#notificationpolicyevents) |  |

### NotificationPolicyEvents

Every e-mail and push alert, keyed by notification type. `false` means the workspace never sends it. New keys may be added.

| Property | Type | Description |
| --- | --- | --- |
| `DocumentCompleted` | boolean |  Example: `true`. |
| `SignerDeclined` | boolean |  Example: `true`. |
| `DocumentCancelled` | boolean |  Example: `true`. |
| `DocumentAboutToExpire` | boolean |  Example: `true`. |
| `DocumentExpired` | boolean |  Example: `true`. |
| `DocumentExpirationReset` | boolean |  Example: `true`. |
| `DocumentProcessingFailed` | boolean |  Example: `true`. |
| `TemplateProcessingFailed` | boolean |  Example: `true`. |
| `SignerWhatsappFailed` | boolean |  Example: `true`. |
| `ContractRenewalNotice` | boolean |  Example: `true`. |
| `ContractExpiring` | boolean |  Example: `true`. |
| `ContractExpired` | boolean |  Example: `true`. |
| `ContractRenewed` | boolean |  Example: `true`. |
| `SignerViewed` | boolean |  Example: `false`. |
| `SignerSigned` | boolean |  Example: `true`. |
| `SignerIdentityReviewRequired` | boolean | Turns off the push only; the identity review e-mail is always sent. Example: `true`. |

### NotificationPreferences

Owner-facing document notifications, keyed by notification type. `true` means the e-mail is sent.

| Property | Type | Description |
| --- | --- | --- |
| `DocumentCompleted` | boolean | Every signer has signed and the document is certified. Example: `true`. |
| `SignerDeclined` | boolean | A signer declined to sign. Example: `true`. |
| `DocumentCancelled` | boolean | The document was cancelled. Example: `true`. |
| `DocumentAboutToExpire` | boolean | The signature deadline is approaching. Example: `true`. |
| `DocumentExpired` | boolean | The signature deadline passed. Example: `true`. |
| `DocumentExpirationReset` | boolean | The signature deadline was extended. Example: `true`. |
| `DocumentProcessingFailed` | boolean | An uploaded document could not be processed. Example: `true`. |
| `TemplateProcessingFailed` | boolean | A template could not be processed. Example: `true`. |
| `SignerWhatsappFailed` | boolean | A WhatsApp notification to a signer could not be delivered. Example: `true`. |
| `ContractRenewalNotice` | boolean | A tracked contract entered its notice period: it is about to end or to renew. Example: `true`. |
| `ContractExpiring` | boolean | A tracked contract ends in 45 or in 30 days. Example: `true`. |
| `ContractExpired` | boolean | A tracked contract ended without renewal. Example: `true`. |
| `ContractRenewed` | boolean | A tracked contract was auto-renewed into its next term. Example: `true`. |

### OAuthRevokeRequest

Body of `POST /v1/oauth/revoke`. Sent form-encoded per RFC 7009, or as JSON.

| Property | Type | Description |
| --- | --- | --- |
| `token` * | string |  |
| `token_type_hint` | string (`"access_token"`, `"refresh_token"`) |  |
| `client_id` * | string |  |
| `client_secret` | string |  |

### OAuthTokenRequest

Body of `POST /v1/oauth/token`. Sent form-encoded per RFC 6749, or as JSON.

| Property | Type | Description |
| --- | --- | --- |
| `grant_type` * | string (`"authorization_code"`, `"refresh_token"`, `"urn:ietf:params:oauth:grant-type:token-exchange"`) | `urn:ietf:params:oauth:grant-type:token-exchange` is for internal service clients only (Assinafy's own MCP server) — an ordinary confidential or public client authenticates with it and always gets `invalid_client`, exactly as an unrecognized client would. Everyday integrators use `authorization_code` and `refresh_token`. |
| `code` | string |  |
| `redirect_uri` | string (format: uri) |  |
| `code_verifier` | string | RFC 7636: 43-128 characters from [A-Za-z0-9-._~]. Shorter values are rejected with `invalid_grant`. |
| `refresh_token` | string |  |
| `client_id` * | string |  |
| `client_secret` | string | Confidential clients only. Public clients authenticate with PKCE and are never issued a secret; the token-exchange grant requires a confidential, internal-service client and therefore always requires this. |
| `resource` | string (format: uri) | RFC 8707 resource indicator. For `authorization_code`/`refresh_token`, optional; when present it must be the `resource` value published by /.well-known/oauth-protected-resource and must match the one sent to /authorize, otherwise `invalid_target`. For the token-exchange grant it is REQUIRED and must equal this API's own resource identifier exactly (never a front-end resource such as the MCP server), otherwise `invalid_target`. |
| `subject_token` | string | Token-exchange grant only. The front-end resource's access token being traded in. Must be a live, original (never itself exchanged) token minted for a resource this server issues tokens for, other than this API's own audience. |
| `subject_token_type` | string (`"urn:ietf:params:oauth:token-type:access_token"`) | Token-exchange grant only. Required; only `urn:ietf:params:oauth:token-type:access_token` is supported. |
| `requested_token_type` | string (`"urn:ietf:params:oauth:token-type:access_token"`) | Token-exchange grant only. Optional; when present it must agree with the only type this server issues. |

### PushPreferences

Document alerts sent as push notifications to the user's phones, keyed by notification type. `true` means the push is sent. Separate from the e-mail preferences. New keys may be added.

| Property | Type | Description |
| --- | --- | --- |
| `SignerViewed` | boolean | A signer opened the document for the first time. Example: `true`. |
| `SignerSigned` | boolean | A signer signed the document. Example: `true`. |
| `DocumentCompleted` | boolean | Every signer has signed and the document is certified. Example: `true`. |
| `SignerDeclined` | boolean | A signer declined to sign. Example: `true`. |
| `DocumentAboutToExpire` | boolean | The signature deadline is approaching. Example: `true`. |
| `DocumentExpired` | boolean | The signature deadline passed. Example: `true`. |
| `SignerIdentityReviewRequired` | boolean | A signer's identity awaits the sender's review. The e-mail for this is always sent. Example: `true`. |
| `SignerWhatsappFailed` | boolean | A WhatsApp notification to a signer could not be delivered. Example: `true`. |

### ResendCostEstimate

Credits a reminder to one signer will take, and whether the account can pay for it. A reminder uses no document.

| Property | Type | Description |
| --- | --- | --- |
| `total` | number | Sum of the `breakdown` costs. Example: `0.45`. |
| `breakdown` | Array<object { `code`: string; `name`: string; `cost`: number }> |  |
| `breakdown[].code` | string |  Example: `"NotificationWhatsappResend"`. |
| `breakdown[].name` | string |  Example: `"Whatsapp Notification Resend"`. |
| `breakdown[].cost` | number |  Example: `0.45`. |
| `credit_balance` | number or null | Credits available. `null` when the account's credits are not limited. Example: `10`. |
| `has_sufficient_credits` | boolean | Whether the reminder would pass its credit check now: the check the reminder itself makes, so a contract that allows overage passes with a low `credit_balance`, and a plan whose payment is pending doesn't, whatever the balance. Example: `true`. |

### Signer

A signing party belonging to a workspace account.

| Property | Type | Description |
| --- | --- | --- |
| `resource` | string | Present in single-resource responses. Example: `"signer"`. |
| `id` | string |  Example: `"62d6ee35c7741ca4006b9e11"`. |
| `full_name` | string |  Example: `"John Signer"`. |
| `email` | string or null (format: email) |  Example: `"signer@example.com"`. |
| `whatsapp_phone_number` | string or null | E.164 format; normalized on save. Example: `"+5548999990000"`. |
| `government_id` | string or null | Signer's normalized CPF (11 digits) or CNPJ (14 characters; may be alphanumeric). Example: `"39053344705"`. |
| `has_accepted_terms` | boolean |  Example: `false`. |

### SignerIdentityReview



| Property | Type | Description |
| --- | --- | --- |
| `id` | string |  Example: `"104c267f8e1e8c6855d7788b76a8"`. |
| `status` | string (`"Pending"`, `"InReview"`, `"Approved"`, `"Declined"`, `"Expired"`, `"Abandoned"`) |  Example: `"InReview"`. |
| `provider` | string (`"AssinafyVerify"`) |  Example: `"AssinafyVerify"`. |
| `verification_method` | string (`"IdDocumentFaceMatchBasic"`) |  Example: `"IdDocumentFaceMatchBasic"`. |
| `reason_codes` | Array<object { `code`: string; `description`: string }> | Why the provider sent it to review, in its order. Unknown codes have the code as description. |
| `reason_codes[].code` | string |  Example: `"NAME_MISMATCH"`. |
| `reason_codes[].description` | string |  Example: `"Nome no documento difere do cadastrado (similaridade 52%)"`. |
| `evidence_available` | boolean |  Example: `true`. |
| `expected` | object { `name`: string or null; `cpf`: string or null } | What the signer was registered with. |
| `expected.name` | string or null |  Example: `"Maria da Silva"`. |
| `expected.cpf` | string or null |  Example: `"52998224725"`. |
| `document` | object { `type`: string or null; `name`: string or null; `cpf`: string or null } | What was read from the document. |
| `document.type` | string or null |  Example: `"CNH"`. |
| `document.name` | string or null |  Example: `"MARIA SILVA"`. |
| `document.cpf` | string or null |  Example: `"52998224725"`. |
| `matches` | object { `cpf`: boolean or null; `name`: number or null; `birth_date`: boolean or null } |  |
| `matches.cpf` | boolean or null |  Example: `true`. |
| `matches.name` | number or null | Name similarity, 0-1. Example: `0.5217`. |
| `matches.birth_date` | boolean or null |  Example: `null`. |
| `checks` | Array<object { `name`: string; `result`: string; `score`: number or null; `reasons`: Array<string> }> |  |
| `checks[].name` | string |  Example: `"name"`. |
| `checks[].result` | string | pass, review, skipped, or a failure result. Example: `"review"`. |
| `checks[].score` | number or null |  Example: `0.5217`. |
| `checks[].reasons` | Array<string> |  Example: `["NAME_MISMATCH"]`. |
| `images` | Array<string (`"document_front"`, `"document_back"`, `"document_pdf"`, `"face"`)> | The evidence images the reviewer can open with **Signer identity review image**, in display order: `document_front`, `document_back`, `document_pdf`, `face`. Only while `status` is `InReview`; empty once decided. Example: `["document_front","document_back","face"]`. |
| `ruleset_version` | string or null |  Example: `"2026-10-12.2"`. |
| `evidence_sha256` | string or null |  Example: `"9f2c0d6e4b1a8c3f5e7d9b0a2c4e6f8a1b3d5f7091e2c4a6b8d0f2e4a6c8e0b2"`. |
| `reviewed_by` | object { `id`: string; `name`: string } |  |
| `reviewed_by.id` | string |  Example: `"Kx9pQ2"`. |
| `reviewed_by.name` | string |  Example: `"Ana Souza"`. |
| `reviewed_at` | string or null (format: date-time) |  Example: `"2026-10-13T21:05:00Z"`. |
| `review_note` | string or null |  Example: `"Conferido por videochamada."`. |
| `completed_at` | string or null (format: date-time) |  Example: `"2026-10-13T21:05:00Z"`. |

### SignerSelf

The current signer, as returned by `GET /v1/signers/self`. Extends Signer with the signature-state flags that are only computed for the authenticated signer.

| Property | Type | Description |
| --- | --- | --- |
| `resource` | string | Present in single-resource responses. Example: `"signer"`. |
| `id` | string |  Example: `"62d6ee35c7741ca4006b9e11"`. |
| `full_name` | string |  Example: `"John Signer"`. |
| `email` | string or null (format: email) |  Example: `"signer@example.com"`. |
| `whatsapp_phone_number` | string or null | E.164 format; normalized on save. Example: `"+5548999990000"`. |
| `government_id` | string or null | Signer's normalized CPF (11 digits) or CNPJ (14 characters; may be alphanumeric). Example: `"39053344705"`. |
| `has_accepted_terms` | boolean |  Example: `false`. |
| `has_signature` | boolean | Whether the signer has a saved signature image stored. Example: `true`. |
| `has_initial` | boolean | Whether the signer has a saved initials image stored. Example: `false`. |
| `is_signature_reusable` | boolean | Whether the signer opted to reuse their saved signature/initials in future processes. When false, clients should not pre-render the saved image even if `has_signature`/`has_initial` is true. Example: `false`. |
| `verification_method` | string (`"Email"`, `"Whatsapp"`, `"DigitalCertificate"`, `"IdDocumentFaceMatchBasic"`) | How this signature request verifies the signer. `Email`/`Whatsapp` ask for the 6-digit code; `IdDocumentFaceMatchBasic` runs the identity document check instead (see **Identity document verification status**). Example: `"Email"`. |

### SigningDocument

The document as its signer reads it with the access code: the document with `current_signer`, `is_signer_access_closed` and `certified_copy`. Once the code is closed, only `id`, `name`, `status` and these three, and `envelope` when asked for.

| Property | Type | Description |
| --- | --- | --- |
| `resource` | string | Present in single-resource responses. Example: `"document"`. |
| `id` | string |  Example: `"615601fab04c0a3147bb1246"`. |
| `account_id` | string |  Example: `"d199996981dbd199996981db"`. |
| `template_id` | string or null |  Example: `null`. |
| `name` | string |  Example: `"document.pdf"`. |
| `status` | string | Status code — see GET /v1/documents/statuses. Example: `"metadata_ready"`. |
| `artifacts` | object | Artifact download URLs keyed by name. Always `original`, plus `thumbnail` once one exists. A certificated document also carries `certificated`, `certificate-page` and `bundle`, and `pades` when it was signed with a digital certificate — the PAdES version holds the signers' ICP-Brasil signatures, which certification flattens out of the certificated PDF. Example: `{"original":"https://api.assinafy.com.br/v1/documents/doc1/download/original"}`. |
| `is_closed` | boolean |  Example: `false`. |
| `signing_url` | string |  Example: `"https://api.assinafy.com.br/v1/sign/doc1"`. |
| `verification_code` | string or null | The code printed on the certificate page. Anyone can check it with `GET /v1/documents/{verification_code}/verify` or on `verification_url`. `null` until the document is `certificated`, and on documents certificated before verification codes existed. Example: `"a3f1c9e07b2d4e8f9a6c5b1d0e7f3a2c9b8d4e6f"`. |
| `verification_url` | string or null (format: uri) | The public verification page for this document. `null` until the document is `certificated`. Example: `"https://www.assinafy.com.br/verificador/a3f1c9e07b2d4e8f9a6c5b1d0e7f3a2c9b8d4e6f"`. |
| `decline_reason` | string or null |  Example: `null`. |
| `declined_by` | [`Signer`](#signer) or null |  |
| `tags` | Array<object { `id`: string; `name`: string; `color`: string or null }> |  |
| `tags[].id` | string |  |
| `tags[].name` | string |  |
| `tags[].color` | string or null | 6-char hex without leading #. Example: `"ff8800"`. |
| `assignment` | [`Assignment`](#assignment) or null | The document's assignment, or `null` before one is created. The server decides when it is included, whatever `expand` the request sends: the document list, `GET /v1/documents/{documentId}`, the signer's document list and document creation from a template always include it; `/documents/search` and the upload response never do. Only the rename response follows `?expand=assignment`. |
| `pages` | Array<[`DocumentPage`](#documentpage)> | The document's pages. Included on the same responses as `assignment`, and also on the upload response. |
| `envelope_id` | string or null | Only on `GET /v1/documents/{documentId}?expand=envelope_id` read by the workspace, not in document lists or webhooks, so their payloads keep their shape: the envelope this document is in, or `null` for a document sent on its own, taken out of its envelope, or whose envelope was deleted. Example: `null`. |
| `envelope` | object { `id*`: string; `name*`: string } | Only on `GET /v1/documents/{documentId}?expand=envelope` read by the workspace and `GET /v1/sign?expand=envelope` or `GET /v1/signers/{signerId}/document?expand=envelope` read with the signer's code, not in document lists or webhooks: the envelope this document is in, or `null` for a document sent on its own, taken out of its envelope, or whose envelope was deleted. The signer's reads name the envelope their code belongs to even when the code's own document was taken out, since the code still reaches the rest. |
| `envelope.id` * | string |  Example: `"fe1c140cb49b79f940aab95fddd"`. |
| `envelope.name` * | string |  Example: `"Contrato de prestação de serviços"`. |
| `has_contract` | boolean | Only on `GET /v1/documents/{documentId}` read by the workspace, while the environment has contract tracking on: not with a signer's access code, not in document lists or webhooks, and left out when the lookup fails, so a missing key means unknown. Whether `GET /v1/accounts/{accountId}/documents/{documentId}/contract` answers with contract terms, the document's own or those of a contract it amends whose document still exists, so a page can lay out the contract section before reading it. Example: `true`. |
| `created_at` | string (format: date-time) |  Example: `"2026-06-03T03:54:16Z"`. |
| `updated_at` | string (format: date-time) |  Example: `"2026-06-03T03:54:16Z"`. |
| `current_signer` | [`Signer`](#signer) plus object { `verification_method`: string; `notification_methods`: array or null; `completed`: boolean } | This signer. Once the code is closed, only `id` and the last three. |
| `is_signer_access_closed` | boolean | Whether the code is closed. Example: `false`. |
| `certified_copy` | object { `available*`: boolean; `notification_method*`: string or null (`"Email"`, `"Whatsapp"`, `null`); `resends_left*`: integer or null } | Whether the signer can ask for the certified copy again (`POST /v1/sign/certified-copy`). |
| `certified_copy.available` * | boolean |  Example: `false`. |
| `certified_copy.notification_method` * | string or null (`"Email"`, `"Whatsapp"`, `null`) | The channel it goes on; `null` when there is none. Example: `"Email"`. |
| `certified_copy.resends_left` * | integer or null | WhatsApp re-sends left; `null` for e-mail. Example: `null`. |

### SigningUrl

One entry per signer whose turn has come. The link depends on how the signer gets the invitation: with `Email` it is a page that does not open the document by itself, where the signer asks for their invitation again by e-mail; with `Whatsapp` only it is `null` (the signer has their link in the WhatsApp message). An embedded signer (`embedded: true`) never gets a link: `url` is `null` and the integrator mints an embed session for them instead.

| Property | Type | Description |
| --- | --- | --- |
| `signer_id` | string |  |
| `url` | string or null | See the schema description. `null` for a signer notified only by WhatsApp and for an embedded signer. Example: `"https://api.assinafy.com.br/v1/sign/doc1?email=signer@example.com"`. |
| `embedded` | boolean | Whether the signer was marked `embedded` when the assignment was created. Example: `false`. |

### Tag

A workspace-scoped label. Names are unique per workspace (case-insensitive).

| Property | Type | Description |
| --- | --- | --- |
| `resource` | string |  Example: `"tag"`. |
| `id` | string |  Example: `"fa8c09f3e709a8a1c82d69b1454"`. |
| `name` | string |  Example: `"Contracts"`. |
| `color` | string or null | 6-char hex without leading #. Example: `"ff8800"`. |
| `created_at` | string (format: date-time) |  Example: `"2026-05-14T12:00:00Z"`. |
| `updated_at` | string (format: date-time) |  Example: `"2026-05-14T12:00:00Z"`. |

### Template

A reusable document template.

| Property | Type | Description |
| --- | --- | --- |
| `resource` | string |  Example: `"template"`. |
| `id` | string |  Example: `"fa88b732db84d01427d4cdd1092"`. |
| `name` | string |  Example: `"template.pdf"`. |
| `document_name` | string or null | Default name for documents created from this template. |
| `message` | string or null | Default invitation message. |
| `status` | string | One of uploading, uploaded, processing, ready, failed. Example: `"ready"`. |
| `pages` | Array<[`TemplatePage`](#templatepage)> |  |
| `roles` | Array<[`TemplateRole`](#templaterole)> |  |
| `tags` | Array<object { `id`: string; `name`: string }> |  |
| `tags[].id` | string |  |
| `tags[].name` | string |  |
| `default_document_tags` | Array<object { `id`: string; `name`: string }> | Applied to documents created from this template; only returned by the single-template endpoint. |
| `default_document_tags[].id` | string |  |
| `default_document_tags[].name` | string |  |
| `created_at` | string (format: date-time) |  |
| `updated_at` | string (format: date-time) |  |

### TemplateFieldPlacement



| Property | Type | Description |
| --- | --- | --- |
| `id` | string |  |
| `field_id` | string |  |
| `role_id` | string |  |
| `label` | string |  |
| `display_settings` | any | Rendering metadata for the placement. |
| `created_at` | string (format: date-time) |  |
| `updated_at` | string (format: date-time) |  |

### TemplatePage



| Property | Type | Description |
| --- | --- | --- |
| `id` | string |  |
| `number` | integer |  Example: `1`. |
| `height` | integer |  Example: `2100`. |
| `width` | integer |  Example: `1275`. |
| `download_url` | string |  |
| `fields` | Array<[`TemplateFieldPlacement`](#templatefieldplacement)> |  |

### TemplateRole



| Property | Type | Description |
| --- | --- | --- |
| `id` | string |  |
| `name` | string |  Example: `"Editor"`. |
| `assignment_type` | string |  Example: `"Editor"`. |
| `created_at` | string (format: date-time) |  |
| `updated_at` | string (format: date-time) |  |

### WebhookDispatch

A single webhook delivery-history entry.

| Property | Type | Description |
| --- | --- | --- |
| `resource` | string | Always `activity_dispatching_history` in single-resource responses. Example: `"activity_dispatching_history"`. |
| `id` | string | Dispatch entry ID. Example: `"a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"`. |
| `event` | string | Event type that triggered the dispatch. Example: `"document_ready"`. |
| `activity_id` | integer | Internal activity ID associated with the dispatch. Example: `456`. |
| `endpoint_id` | string or null | ID of the webhook endpoint the delivery was sent to (`null` once that endpoint is deleted). Example: `"65f1c2a9b3e4d5f60718293a4b5c6d7e"`. |
| `endpoint` | string or null | URL that received the request. Example: `"https://example.com/webhook"`. |
| `payload` | object or null | JSON payload sent to the endpoint. |
| `delivered` | boolean | Whether delivery succeeded. Example: `true`. |
| `webhook_id` | string or null | The `webhook-id` header of the request: the same on every attempt of this event to this endpoint. Example: `"9f86d081884c7d659a2feaa0c55ad015"`. |
| `attempt` | integer or null | Which attempt of this event to this endpoint the entry records, counted from 1. Example: `2`. |
| `kind` | string (`"scheduled"`, `"probe"`, `"manual"`) | `scheduled`: the delivery of the event as it happened; `probe`: the one delivery we send to a paused endpoint to see whether it answers; `manual`: asked for through **Retry webhook delivery** or **Send a test delivery**. Example: `"scheduled"`. |
| `will_retry` | boolean | Whether another attempt follows this one. `false` on a delivered entry and on the last attempt of a failed one. Example: `true`. |
| `duration_ms` | integer or null | How long the endpoint took to answer or fail, in milliseconds. `null` when no request was sent (a host that does not resolve, an address that is not public) and on entries recorded before it was measured. Example: `184`. |
| `http_status` | integer or null | HTTP status returned (null if connection failed). Example: `200`. |
| `response_body` | string or null | Endpoint response body, truncated to 2000 chars. Example: `"OK"`. |
| `error` | string or null | Delivery error message, if any. Example: `null`. |
| `created_at` | string (format: date-time) |  Example: `"2024-01-15T10:30:00Z"`. |
| `updated_at` | string (format: date-time) |  Example: `"2024-01-15T10:30:00Z"`. |

### WebhookEndpoint

A URL that receives the account's webhook events. Every active endpoint subscribed to an event receives it.

| Property | Type | Description |
| --- | --- | --- |
| `resource` | string | Always `activity_event_subscription` in single-resource responses. Example: `"activity_event_subscription"`. |
| `id` | string | Endpoint ID. Example: `"65f1c2a9b3e4d5f60718293a4b5c6d7e"`. |
| `name` | string or null | Label to tell endpoints apart. Example: `"ERP"`. |
| `url` | string (format: uri) | URL that receives the events; `https` is required for a new or changed URL. Example: `"https://example.com/webhooks/assinafy"`. |
| `email` | string (format: email) | Contact email for delivery-failure notices. Example: `"signer@example.com"`. |
| `events` | Array<string> | Event types delivered to this endpoint (see **List webhook event types**). Example: `["document_ready","signer_signed_document"]`. |
| `is_active` | boolean | Whether events are delivered to this endpoint. Example: `true`. |
| `is_held` | boolean | Whether deliveries are paused after 10 failures in a row: we probe the endpoint on a growing schedule and deliver what it missed when it answers (see **Delivery contract**). Editing the URL, or sending `is_active: true`, lifts the pause. Example: `false`. |
| `held_since` | integer or null | When the pause began (Unix timestamp, seconds); `null` while deliveries run. Example: `null`. |
| `signing_enabled` | boolean | Whether deliveries carry a `webhook-signature` header (see **Webhook Payloads → Verifying signatures**). Example: `true`. |
| `created_at` | string (format: date-time) |  Example: `"2026-10-01T12:00:00Z"`. |
| `updated_at` | string (format: date-time) |  Example: `"2026-10-01T12:00:00Z"`. |

### WebhookEndpointSecret

An endpoint's signing secret.

| Property | Type | Description |
| --- | --- | --- |
| `secret` | string | Standard Webhooks secret: `whsec_` followed by the base64-encoded key. Example: `"whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"`. |

### WebhookEvent

Body of every webhook delivery. Timestamps in the body (`created_at`, and the `*_at` fields of `subject`/`object`) are Unix timestamps in seconds, not the ISO strings the REST responses use. `subject` and `object` are serialized from their current state when the delivery is sent.

| Property | Type | Description |
| --- | --- | --- |
| `id` * | integer | ID of the activity that produced the event. Example: `184467`. |
| `event` * | string | Event type. See **List webhook event types**; `webhook_test` is sent only by **Send a test delivery**. Example: `"signer_viewed_document"`. |
| `message` | string or null | Reserved; currently always `null`. Example: `null`. |
| `payload` | object or null | Event-specific parameters; keys vary per event. |
| `origin` | object { `ip`: string; `user-agent`: string } | Where the action came from, when it was triggered by a request. |
| `origin.ip` | string |  Example: `"203.0.113.7"`. |
| `origin.user-agent` | string |  Example: `"Mozilla/5.0"`. |
| `created_at` * | integer | When the event was recorded (Unix timestamp, seconds). Example: `1790000000`. |
| `subject` * | object | Who performed the action: a `User`, `Signer` or `Account` (the endpoint itself in a `webhook_test`), plus a `type` property naming it. |
| `object` * | object | What the action was performed on: a `Document`, `Signer` or `Template` with its relations expanded (the endpoint itself in a `webhook_test`), plus a `type` property naming it. |
| `account_id` * | string | ID of the account that owns the event. Example: `"65f1c2a9b3e4d5f6"`. |

### WebhookEventType

A subscribable webhook event type.

| Property | Type | Description |
| --- | --- | --- |
| `id` | string | Event type code. Example: `"document_ready"`. |
| `description` | string | When the event is triggered. Example: `"Triggered when the last Signer of the assignment signs the Document."`. |

### WebhookSubscription

An account's webhook subscription configuration.

| Property | Type | Description |
| --- | --- | --- |
| `events` | Array<string> | Event types subscribed for delivery. Example: `["document_ready","document_prepared"]`. |
| `is_active` | boolean | Whether webhook delivery is active. Example: `true`. |
| `is_held` | boolean | Whether deliveries are paused after 10 failures in a row (see **Delivery contract**). Example: `false`. |
| `held_since` | integer or null | When the pause began (Unix timestamp, seconds); `null` while deliveries run. Example: `null`. |
| `url` | string or null | Webhook endpoint URL; `https` is required for a new or changed URL. Example: `"https://example.com?test=1"`. |
| `email` | string or null | Contact email for delivery notices. Example: `"signer@example.com"`. |
| `updated_at` | string or null (format: date-time) |  Example: `"2023-05-10T14:58:24Z"`. |

### WhatsappNotification

A rendered WhatsApp notification sent for an assignment, split into header/body/buttons as the signer would see them.

| Property | Type | Description |
| --- | --- | --- |
| `sent_at` | string (format: date-time) | When the message was sent. Example: `"2026-07-07T12:00:00Z"`. |
| `header` | string |  Example: `"Documento para assinatura: Contrato de Servico"`. |
| `body` | string |  |
| `buttons` | Array<object { `text`: string }> |  |
| `buttons[].text` | string | The button label shown to the signer. Example: `"Abrir documento"`. |
| `phone_number` | string | Recipient phone (E.164). Example: `"+5511999990001"`. |
| `signer_id` | string |  Example: `"a51edaee68a7"`. |
