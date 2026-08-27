# Assinafy Ruby SDK API Reference

> Contract source: Assinafy API v1 OpenAPI 3.0.0, retrieved 2026-08-26 from
> `https://api.assinafy.com.br/v1/docs/openapi.json` (67 paths, 89 operations, 39 schemas).
> `scripts/check_api_contract.rb` validates contract compatibility weekly.

This is the SDK-facing contract reference. Paths below are wire paths; Ruby methods return the unwrapped
`data` member for Assinafy response envelopes, pagination helpers return `{ data:, meta: }`, binary methods
return bytes, and documented no-data operations return `nil`.

Required parameters and object properties are marked with `*`.

## Authentication and safety

- `X-Api-Key` is the recommended server-side credential. Bearer tokens are legacy session credentials. If both
  are configured, the current SDK sends only `X-Api-Key`; prefer configuring exactly one credential.
- Signer-facing operations use the one-time `signer-access-code` query parameter where shown. Never log, commit,
  or place API keys, bearer tokens, signer codes, or real recipient addresses in examples or fixtures.
- HTTP connections use Ruby/Faraday TLS verification and the host system trust store; the SDK does not pin the
  upstream TLS certificate.
- `DocumentResource#verify` reports Assinafy upstream verification data. It does not independently validate a PDF
  signature, certificate chain, OCSP/CRL status, or legal validity. The API artifact name `certificated` is not an
  additional local guarantee.

## API operations

| Method | Path | Ruby SDK method | Authentication | Parameters | Request body | Success wire response |
| --- | --- | --- | --- | --- | --- | --- |
| GET | `/v1/accounts` | `AccountResource#list` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Account`](#account)> } |
| POST | `/v1/accounts` | `AccountResource#create` | Bearer token or `X-Api-Key` | None | required; `application/json` object { `name*`: string; `notification_sender_type`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Account`](#account) } |
| GET | `/v1/accounts/{accountId}` | `AccountResource#get` | Bearer token or `X-Api-Key` | path `accountId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Account`](#account) } |
| PUT | `/v1/accounts/{accountId}` | `AccountResource#update` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `application/json` object { `name`: string; `notification_sender_type`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Account`](#account) } |
| DELETE | `/v1/accounts/{accountId}` | `AccountResource#delete` | Bearer token or `X-Api-Key` | path `accountId*`: string | optional; `application/json` object { `force`: boolean } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| GET | `/v1/accounts/{accountId}/documents` | `DocumentResource#list` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `status`: string<br>query `method`: string<br>query `search`: string<br>query `tags`: string<br>query `sort`: string<br>query `page`: integer<br>query `per-page`: integer | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Document`](#document)> } |
| POST | `/v1/accounts/{accountId}/documents` | `DocumentResource#upload` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `multipart/form-data` object { `file*`: string (binary) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Document`](#document) } |
| GET | `/v1/accounts/{accountId}/documents/search` | `DocumentResource#search` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `search`: string<br>query `status`: string<br>query `page`: integer<br>query `per-page`: integer | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Document`](#document)> } |
| GET | `/v1/accounts/{accountId}/documents/{documentId}/tags` | `DocumentResource#list_tags` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `documentId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Tag`](#tag)> } |
| PUT | `/v1/accounts/{accountId}/documents/{documentId}/tags` | `DocumentResource#replace_tags` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `documentId*`: string | required; `application/json` object { `tags`: Array<string> } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Tag`](#tag)> } |
| POST | `/v1/accounts/{accountId}/documents/{documentId}/tags` | `DocumentResource#append_tags` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `documentId*`: string | required; `application/json` object { `tags`: Array<string> } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Tag`](#tag)> } |
| DELETE | `/v1/accounts/{accountId}/documents/{documentId}/tags/{tagId}` | `DocumentResource#detach_tag` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `documentId*`: string<br>path `tagId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `detached`: boolean } } |
| GET | `/v1/accounts/{accountId}/fields` | `FieldResource#list` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `include_inactive`: boolean<br>query `include_standard`: boolean | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Field`](#field)> } |
| POST | `/v1/accounts/{accountId}/fields` | `FieldResource#create` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `application/json` object { `name*`: string; `type*`: string; `regex`: string; `is_required`: boolean } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Field`](#field) } |
| POST | `/v1/accounts/{accountId}/fields/validate-multiple` | `FieldResource#validate_multiple` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `application/json` Array<object { `field_id*`: string; `value*`: any JSON value }> | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`FieldValidationResult`](#fieldvalidationresult)> } |
| GET | `/v1/accounts/{accountId}/fields/{fieldId}` | `FieldResource#get` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `fieldId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Field`](#field) } |
| PUT | `/v1/accounts/{accountId}/fields/{fieldId}` | `FieldResource#update` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `fieldId*`: string | required; `application/json` object { `name`: string; `regex`: string; `is_active`: boolean } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Field`](#field) } |
| DELETE | `/v1/accounts/{accountId}/fields/{fieldId}` | `FieldResource#delete` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `fieldId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| POST | `/v1/accounts/{accountId}/fields/{fieldId}/validate` | `FieldResource#validate` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `fieldId*`: string | required; `application/json` object { `value*`: any JSON value } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`FieldValidation`](#fieldvalidation) } |
| GET | `/v1/accounts/{accountId}/logo` | `AccountResource#download_logo` | Bearer token or `X-Api-Key` | path `accountId*`: string | None | `200` `image/*` string (binary) |
| POST | `/v1/accounts/{accountId}/logo` | `AccountResource#upload_logo` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `multipart/form-data` object { `file*`: string (binary) } | `200` `application/json` [`Envelope`](#envelope) |
| DELETE | `/v1/accounts/{accountId}/logo` | `AccountResource#delete_logo` | Bearer token or `X-Api-Key` | path `accountId*`: string | None | `200` `application/json` [`Envelope`](#envelope) |
| GET | `/v1/accounts/{accountId}/signers` | `SignerResource#list` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `search`: string<br>query `page`: integer<br>query `per-page`: integer | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Signer`](#signer)> } |
| POST | `/v1/accounts/{accountId}/signers` | `SignerResource#create` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `application/json` object { `full_name*`: string; `email`: string (email); `whatsapp_phone_number`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Signer`](#signer) } |
| GET | `/v1/accounts/{accountId}/signers/{signerId}` | `SignerResource#get` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `signerId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Signer`](#signer) } |
| PUT | `/v1/accounts/{accountId}/signers/{signerId}` | `SignerResource#update` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `signerId*`: string | required; `application/json` object { `full_name`: string; `email`: string (email); `whatsapp_phone_number`: string; `government_id`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Signer`](#signer) } |
| DELETE | `/v1/accounts/{accountId}/signers/{signerId}` | `SignerResource#delete` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `signerId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| GET | `/v1/accounts/{accountId}/stats` | `AccountResource#stats` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `granularity`: string<br>query `month`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`DocumentStatsRow`](#documentstatsrow)> } |
| GET | `/v1/accounts/{accountId}/tags` | `TagResource#list` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `search`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Tag`](#tag)> } |
| POST | `/v1/accounts/{accountId}/tags` | `TagResource#create` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `application/json` object { `name*`: string; `color`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Tag`](#tag) } |
| PUT | `/v1/accounts/{accountId}/tags/{tagId}` | `TagResource#update` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `tagId*`: string | required; `application/json` object { `name`: string; `color`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Tag`](#tag) } |
| DELETE | `/v1/accounts/{accountId}/tags/{tagId}` | `TagResource#delete` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `tagId*`: string<br>query `force`: boolean | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `deleted`: boolean } } |
| GET | `/v1/accounts/{accountId}/templates` | `TemplateResource#list` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `search`: string<br>query `page`: integer<br>query `per-page`: integer | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Template`](#template)> } |
| POST | `/v1/accounts/{accountId}/templates/{templateId}/documents` | `DocumentResource#create_from_template` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `templateId*`: string | required; `application/json` object { `signers*`: Array<object { `role_id*`: string; `id*`: string; `verification_method`: string; `notification_methods`: Array<string>; `step`: integer }>; `editor_fields`: Array<object { `field_id*`: string; `value*`: string }>; `name`: string; `message`: string; `expires_at`: string (date-time); `tags`: Array<string> } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Document`](#document) } |
| POST | `/v1/accounts/{accountId}/templates/{templateId}/documents/estimate-cost` | `DocumentResource#estimate_cost_from_template` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `templateId*`: string | required; `application/json` object { `signers*`: Array<object { `role_id*`: string; `verification_method`: string; `notification_methods`: Array<string> }> } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`CostEstimate`](#costestimate) } |
| GET | `/v1/accounts/{accountId}/theme` | `AccountResource#theme` | Bearer token or `X-Api-Key` | path `accountId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`AccountTheme`](#accounttheme) } |
| GET | `/v1/accounts/{accountId}/webhooks` | `WebhookResource#list_dispatches` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>query `event`: string<br>query `delivered`: string<br>query `from`: integer<br>query `to`: integer<br>query `page`: integer<br>query `per-page`: integer | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`WebhookDispatch`](#webhookdispatch)> } |
| PUT | `/v1/accounts/{accountId}/webhooks/inactivate` | `WebhookResource#inactivate` | Bearer token or `X-Api-Key` | path `accountId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`WebhookSubscription`](#webhooksubscription) } |
| GET | `/v1/accounts/{accountId}/webhooks/subscriptions` | `WebhookResource#get` | Bearer token or `X-Api-Key` | path `accountId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`WebhookSubscription`](#webhooksubscription) } |
| PUT | `/v1/accounts/{accountId}/webhooks/subscriptions` | `WebhookResource#register` | Bearer token or `X-Api-Key` | path `accountId*`: string | required; `application/json` object { `events*`: Array<string>; `is_active*`: boolean; `url*`: string (uri); `email*`: string (email) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`WebhookSubscription`](#webhooksubscription) } |
| POST | `/v1/accounts/{accountId}/webhooks/{historyId}/retry` | `WebhookResource#retry_dispatch` | Bearer token or `X-Api-Key` | path `accountId*`: string<br>path `historyId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`WebhookDispatch`](#webhookdispatch) } |
| GET | `/v1/assignments` | `AssignmentResource#list` | Bearer token or `X-Api-Key` | query `page`: integer<br>query `per-page`: integer | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Assignment`](#assignment)> } |
| POST | `/v1/auth/link-social-login` | `AuthResource#link_social_login` | Bearer token or `X-Api-Key` | None | required; `application/json` object { `provider*`: string; `token*`: string } | `200` `application/json` [`Envelope`](#envelope) |
| PUT | `/v1/authentication/change-password` | `AuthResource#change_password` | Bearer token or `X-Api-Key` | None | required; `application/json` object { `email*`: string (email); `password*`: string (password); `new_password*`: string (password) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `email`: string (email) } } |
| PUT | `/v1/authentication/request-password-reset` | `AuthResource#request_password_reset` | Public | None | required; `application/json` object { `email*`: string (email) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `email`: string (email) } } |
| PUT | `/v1/authentication/reset-password` | `AuthResource#reset_password` | Public | None | required; `application/json` object { `email*`: string (email); `token`: string; `new_password*`: string (password) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `email`: string (email) } } |
| POST | `/v1/authentication/social-login` | `AuthResource#social_login` | Public | None | required; `application/json` object { `provider*`: string; `token*`: string; `has_accepted_terms*`: boolean } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`AuthSession`](#authsession) } |
| GET | `/v1/documents/statuses` | `DocumentResource#statuses` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`DocumentStatus`](#documentstatus)> } |
| GET | `/v1/documents/{documentId}` | `DocumentResource#details` | Bearer token or `X-Api-Key` | path `documentId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Document`](#document) } |
| DELETE | `/v1/documents/{documentId}` | `DocumentResource#delete` | Bearer token or `X-Api-Key` | path `documentId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| PATCH | `/v1/documents/{documentId}` | `DocumentResource#rename` | Bearer token or `X-Api-Key` | path `documentId*`: string | required; `application/json` object { `name*`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Document`](#document) } |
| GET | `/v1/documents/{documentId}/activities` | `DocumentResource#activities` | Bearer token or `X-Api-Key` | path `documentId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`DocumentActivity`](#documentactivity)> } |
| POST | `/v1/documents/{documentId}/assignments` | `AssignmentResource#create` | Bearer token or `X-Api-Key` | path `documentId*`: string | required; `application/json` object { `method*`: string; `signers*`: Array<object { `id*`: string; `verification_method`: string; `notification_methods`: Array<string>; `step`: integer }>; `entries`: Array<object { `page_id`: string; `fields`: Array<object { `signer_id`: string; `field_id`: string; `display_settings`: [`DisplaySettings`](#displaysettings) }> }>; `message`: string; `expires_at`: string (date-time); `copy_receivers`: Array<string> } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Assignment`](#assignment) } |
| POST | `/v1/documents/{documentId}/assignments/estimate-cost` | `AssignmentResource#estimate_cost` | Bearer token or `X-Api-Key` | path `documentId*`: string | required; `application/json` object { `method`: string; `signers`: Array<object { `verification_method`: string; `notification_methods`: Array<string> }>; `entries`: Array<object> } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`CostEstimate`](#costestimate) } |
| POST | `/v1/documents/{documentId}/assignments/{assignmentId}` | `AssignmentResource#sign` | `signer-access-code` query parameter | path `documentId*`: string<br>path `assignmentId*`: string | required; `application/json` Array<object { `itemId*`: string; `fieldId*`: string; `pageId*`: string; `value*`: string }> | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object } |
| PUT | `/v1/documents/{documentId}/assignments/{assignmentId}/reject` | `AssignmentResource#decline` | `signer-access-code` query parameter | path `documentId*`: string<br>path `assignmentId*`: string | required; `application/json` object { `decline_reason*`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| PUT | `/v1/documents/{documentId}/assignments/{assignmentId}/reset-expiration` | `AssignmentResource#reset_expiration` | Bearer token or `X-Api-Key` | path `documentId*`: string<br>path `assignmentId*`: string | required; `application/json` object { `expires_at`: string (date-time) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Assignment`](#assignment) } |
| POST | `/v1/documents/{documentId}/assignments/{assignmentId}/signers/{signerId}/estimate-resend-cost` | `AssignmentResource#estimate_resend_cost` | Bearer token or `X-Api-Key` | path `documentId*`: string<br>path `assignmentId*`: string<br>path `signerId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`CostEstimate`](#costestimate) } |
| PUT | `/v1/documents/{documentId}/assignments/{assignmentId}/signers/{signerId}/resend` | `AssignmentResource#resend_notification` | Bearer token or `X-Api-Key` | path `documentId*`: string<br>path `assignmentId*`: string<br>path `signerId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: object { `is_sent`: boolean; `document_id`: string; `signer_id`: string } } |
| GET | `/v1/documents/{documentId}/assignments/{assignmentId}/whatsapp-notifications` | `AssignmentResource#whatsapp_notifications` | Bearer token or `X-Api-Key` | path `documentId*`: string<br>path `assignmentId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`WhatsappNotification`](#whatsappnotification)> } |
| GET | `/v1/documents/{documentId}/download/{artifactName}` | `DocumentResource#download` | Bearer token or `X-Api-Key` | path `documentId*`: string<br>path `artifactName*`: string | None | `200` `application/pdf` string (binary) |
| GET | `/v1/documents/{documentId}/pages/{pageId}/download` | `DocumentResource#download_page` | Bearer token or `X-Api-Key` | path `documentId*`: string<br>path `pageId*`: string | None | `200` `image/*` string (binary) |
| PUT | `/v1/documents/{documentId}/signers/confirm-data` | `SignerResource#confirm_data` | `signer-access-code` query parameter | path `documentId*`: string | required; `application/json` object { `full_name`: string; `email`: string (email); `government_id`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Signer`](#signer) } |
| GET | `/v1/documents/{documentId}/thumbnail` | `DocumentResource#thumbnail` | Bearer token or `X-Api-Key` | path `documentId*`: string | None | `200` `image/*` string (binary) |
| GET | `/v1/documents/{documentSignatureHash}/verify` | `DocumentResource#verify` | Public | path `documentSignatureHash*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`DocumentVerification`](#documentverification) } |
| GET | `/v1/field-types` | `FieldResource#types` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`FieldType`](#fieldtype)> } |
| POST | `/v1/login` | `AuthResource#login` | Public | None | required; `application/json` object { `email*`: string (email); `password*`: string (password) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`AuthSession`](#authsession) } |
| GET | `/v1/public/documents/{documentId}` | `DocumentResource#public_info` | Public | path `documentId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Document`](#document) } |
| PUT | `/v1/public/documents/{documentId}/send-token` | `DocumentResource#send_token` | Public | path `documentId*`: string | optional; `application/json` object { `email`: string (email) } | `200` `application/json` [`Envelope`](#envelope) |
| GET | `/v1/sign` | `AssignmentResource#signer_document` | `signer-access-code` query parameter | query `has_accepted_terms`: boolean | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Document`](#document) } |
| POST | `/v1/signature` | `SignerResource#upload_signature` | `signer-access-code` query parameter | query `type`: string<br>query `reuse`: boolean | required; `image/png` string (binary) | `200` `application/json` [`Envelope`](#envelope) |
| GET | `/v1/signature/{signatureType}` | `SignerResource#download_signature` | `signer-access-code` query parameter | path `signatureType*`: string | None | `200` `image/*` string (binary) |
| PUT | `/v1/signers/accept-terms` | `SignerResource#accept_terms` | `signer-access-code` query parameter | None | None | `200` `application/json` [`Envelope`](#envelope) |
| PUT | `/v1/signers/documents/decline-multiple` | `SignerDocumentResource#decline_multiple` | `signer-access-code` query parameter | None | required; `application/json` object { `document_ids*`: Array<string>; `decline_reason*`: string } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| PUT | `/v1/signers/documents/sign-multiple` | `SignerDocumentResource#sign_multiple` | `signer-access-code` query parameter | None | required; `application/json` object { `document_ids*`: Array<string> } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| GET | `/v1/signers/self` | `SignerResource#self_data` | `signer-access-code` query parameter | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`SignerSelf`](#signerself) } |
| GET | `/v1/signers/{signerId}/document` | `SignerDocumentResource#current` | `signer-access-code` query parameter | path `signerId*`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`Document`](#document) } |
| GET | `/v1/signers/{signerId}/documents` | `SignerDocumentResource#list` | `signer-access-code` query parameter | path `signerId*`: string<br>query `page`: integer<br>query `per-page`: integer | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Document`](#document)> } |
| GET | `/v1/signers/{signerId}/documents/search` | `SignerDocumentResource#search` | `signer-access-code` query parameter | path `signerId*`: string<br>query `search`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`Document`](#document)> } |
| GET | `/v1/signers/{signerId}/documents/{documentId}/download/{artifactName}` | `SignerDocumentResource#download` | Public | path `signerId*`: string<br>path `documentId*`: string<br>path `artifactName*`: string | None | `200` `application/pdf` string (binary) |
| GET | `/v1/users/api-keys` | `AuthResource#get_api_key` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`ApiKey`](#apikey) } |
| POST | `/v1/users/api-keys` | `AuthResource#create_api_key` | Bearer token or `X-Api-Key` | None | required; `application/json` object { `password*`: string (password) } | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`ApiKey`](#apikey) } |
| DELETE | `/v1/users/api-keys` | `AuthResource#delete_api_key` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<any> } |
| GET | `/v1/users/self` | `UserResource#me` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`AuthUser`](#authuser) } |
| GET | `/v1/users/self/notification-preferences` | `UserResource#notification_preferences` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`NotificationPreferences`](#notificationpreferences) } |
| PUT | `/v1/users/self/notification-preferences` | `UserResource#update_notification_preferences` | Bearer token or `X-Api-Key` | None | required; `application/json` [`NotificationPreferences`](#notificationpreferences) | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: [`NotificationPreferences`](#notificationpreferences) } |
| GET | `/v1/users/self/stats` | `UserResource#stats` | Bearer token or `X-Api-Key` | query `granularity`: string<br>query `month`: string | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`DocumentStatsRow`](#documentstatsrow)> } |
| POST | `/v1/verify` | `SignerResource#verify_email` | `signer-access-code` query parameter | None | required; `application/json` object { `verification-code*`: string } | `200` `application/json` [`Envelope`](#envelope) |
| GET | `/v1/webhooks/event-types` | `WebhookResource#list_event_types` | Bearer token or `X-Api-Key` | None | None | `200` `application/json` [`Envelope`](#envelope) plus object { `data`: Array<[`WebhookEventType`](#webhookeventtype)> } |

## Error responses

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
- `error_name` and `error_code` expose framework `name` and `code` values when present.
- `context` contains `status_code` and `response_data` for structured logging or support diagnostics.

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

`GET /v1/assignments` needs an account context that the machine contract does not list. The SDK supplies it as
the camelCase `accountId` query parameter (`AssignmentResource#list`), taken from the client default or the
per-call override.

### Assignment optional fields

`message` and `expires_at` must be strings, and `copy_receivers` must be an array of non-empty signer IDs.
`AssignmentResource.build_payload` rejects other shapes locally, so `Client#upload_and_request_signatures`
fails before it uploads a document or creates signers.

### Base URL

`base_url` must be an absolute `http`/`https` URL with a host. Other schemes, scheme-less hosts, and relative
paths raise `Assinafy::ValidationError` at construction rather than sending credentials to them.

### Document tags

`DocumentResource#replace_tags` and `#append_tags` accept arrays of tag IDs. The deployed sandbox also accepts
existing tag names; IDs are the portable form. Use a tag ID with `DocumentResource#detach_tag`.

### Digital-certificate signing

`DigitalCertificate` is available as an assignment verification-method value. Provider documentation refers to
`/signers/certificate/start` and `/signers/certificate/complete`, but the API v1 machine contract does not publish
their authentication, request, or response schemas. The SDK therefore does not expose certificate-completion
methods. Contact Assinafy for the supported provider contract before enabling this flow in production.

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
| `Client#auth`, `#accounts`, `#users`, `#documents`, `#signers`, `#signer_documents`, `#assignments`, `#webhooks`, `#templates`, `#fields`, `#tags`, `#webhook_verifier` | Return the client's resource and helper instances. | [`client.rb`](../lib/assinafy/client.rb) |
| `Assinafy::Configuration.new`, `.from_hash` | Build configuration directly or from string/symbol keys. | [`configuration.rb`](../lib/assinafy/configuration.rb) |
| `Configuration#auth_headers` | Return the selected API-key, bearer, or empty authentication header set. | [`configuration.rb`](../lib/assinafy/configuration.rb) |
| Configuration readers/writers: `api_key`, `token`, `account_id`, `base_url`, `webhook_secret`, `timeout`, `logger` | Read or update configuration values; construct a new client to apply changes. | [`configuration.rb`](../lib/assinafy/configuration.rb) |
| `DocumentResource#get` | Alias for `#details`. | [`document_resource.rb`](../lib/assinafy/resources/document_resource.rb) |
| `DocumentResource#wait_until_ready` | Poll document details until processing succeeds, fails, or times out. | [`document_resource.rb`](../lib/assinafy/resources/document_resource.rb) |
| `DocumentResource#fully_signed?`, `#signing_progress` | Derive completion state from document assignment data. | [`document_resource.rb`](../lib/assinafy/resources/document_resource.rb) |
| `SignerResource#validate_create!` | Validate and normalize a signer-create body without a network request. | [`signer_resource.rb`](../lib/assinafy/resources/signer_resource.rb) |
| `SignerResource#find_by_email` | Page through a successful search and return a case-insensitive match or `nil`. | [`signer_resource.rb`](../lib/assinafy/resources/signer_resource.rb) |
| `SignerDocumentResource#document` | Alias for `#current`. | [`signer_document_resource.rb`](../lib/assinafy/resources/signer_document_resource.rb) |
| `AuthResource#api_key` | Alias for `#get_api_key`. | [`auth_resource.rb`](../lib/assinafy/resources/auth_resource.rb) |
| `WebhookResource#update` | Alias for `#register`. | [`webhook_resource.rb`](../lib/assinafy/resources/webhook_resource.rb) |
| `AssignmentResource.build_payload` | Validate and normalize virtual or collect assignment bodies locally. | [`assignment_resource.rb`](../lib/assinafy/resources/assignment_resource.rb) |
| `WebhookVerifier.new`, `#verify` | Configure and verify the optional gateway HMAC-SHA256 signature. | [`webhook_verifier.rb`](../lib/assinafy/support/webhook_verifier.rb) |
| `WebhookVerifier#extract_event`, `#event_type`, `#event_payload`, `#event_object`, `#event_subject`, `#event_data` | Parse and access webhook envelope fields; `event_data` is retained as a compatibility helper. | [`webhook_verifier.rb`](../lib/assinafy/support/webhook_verifier.rb) |
| `Assinafy::Error.new`, `#context` | Construct/read the SDK base error and its structured context. | [`errors.rb`](../lib/assinafy/errors.rb) |
| `Assinafy::ApiError.new`, `.from_response`, `#status_code`, `#response_data`, `#error_name`, `#error_code` | Construct/read an API response error. | [`errors.rb`](../lib/assinafy/errors.rb) |
| `Assinafy::ValidationError.new`, `#errors`; `Assinafy::NetworkError` | Represent caller-side validation and transport failures. | [`errors.rb`](../lib/assinafy/errors.rb) |
| `Assinafy::Utils.handle_assinafy_response`, `.clean_params`, `.query_params`, `.body_params` | Internal public helpers used by resources for envelope and parameter normalization; applications should prefer resource methods. | [`utils.rb`](../lib/assinafy/utils.rb) |
| `Assinafy::NullLogger#debug`, `#info`, `#warn`, `#error`, `#fatal`, `#unknown` | Internal no-op logger methods used when no logger is configured. | [`null_logger.rb`](../lib/assinafy/null_logger.rb) |
| `Assinafy::VERSION` | Published SDK version constant. | [`version.rb`](../lib/assinafy/version.rb) |
| `Assinafy::USER_AGENT` | Version-derived `Assinafy-Ruby-SDK/v[VERSION]` request identifier. | [`version.rb`](../lib/assinafy/version.rb) |

## Schema catalog

The following catalog includes every schema and property published by the API on 2026-08-26. A schema may be
used for requests, responses, or both; endpoint-specific required bodies and authentication remain authoritative
in the operation table above.

### Account

A workspace account (organization).

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `resource` | string | No | No | — |
| `id` | string | No | No | — |
| `name` | string | No | No | — |
| `primary_color` | string | No | Yes | — |
| `secondary_color` | string | No | Yes | — |
| `notification_sender_type` | string | No | No | enum: `"User"`, `"Account"` |
| `roles` | Array<string> | No | No | — |
| `is_delete_allowed` | boolean | No | No | — |
| `created_at` | string (date-time) | No | No | — |

### AccountTheme

An account's branding theme.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `account_name` | string | No | No | — |
| `primary_color` | string | No | No | Hex color without leading `#`. |
| `secondary_color` | string | No | Yes | — |
| `logo` | string | No | No | URL to the account logo. |

### ApiKey

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `api_key` | string | No | Yes | — |

### Assignment

A request for signers to sign a document.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `resource` | string | No | No | — |
| `id` | string | No | No | — |
| `sender_email` | string (email) | No | No | — |
| `method` | string | No | No | enum: `"virtual"`, `"collect"` |
| `expires_at` | string (date-time) | No | Yes | — |
| `message` | string | No | Yes | — |
| `signers` | Array<[`AssignmentSigner`](#assignmentsigner)> | No | No | — |
| `copy_receivers` | Array<object> | No | No | — |
| `items` | Array<[`AssignmentItem`](#assignmentitem)> | No | No | — |
| `summary` | [`AssignmentSummary`](#assignmentsummary) | No | No | — |
| `signing_urls` | Array<[`SigningUrl`](#signingurl)> | No | No | — |

### AssignmentItem

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `id` | string | No | No | — |
| `page` | [`DocumentPage`](#documentpage) | No | Yes | — |
| `signer` | object | No | No | Signer responsible for this item. |
| `field` | object | No | Yes | Field definition associated with the item. |
| `display_settings` | object | No | No | Rendering metadata for the item. Collect items use the DisplaySettings schema; virtual and legacy items may return an empty or non-object value. |
| `value` | object | No | Yes | Captured value when completed. |
| `completed` | boolean | No | No | — |

### AssignmentSigner

A signer within an assignment: the base Signer plus per-assignment verification/notification details.

Type: [`Signer`](#signer) plus object { `verification_method`: string; `notification_methods`: Array<string>; `step`: integer; `notified`: boolean; `completed`: boolean; `notification_history`: Array<[`NotificationHistoryEntry`](#notificationhistoryentry)> }.

### AssignmentSummary

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `signer_count` | integer | No | No | — |
| `completed_count` | integer | No | No | — |
| `signers` | Array<object> | No | No | — |

### AuthAccount

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `id` | string | No | No | — |
| `name` | string | No | No | — |
| `roles` | Array<string> | No | No | — |
| `is_delete_allowed` | boolean | No | No | — |
| `created_at` | string (date-time) | No | No | — |

### AuthSession

A JWT access token plus the authenticated user and the accounts they belong to.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `access_token` | string | No | No | — |
| `user` | [`AuthUser`](#authuser) | No | No | — |
| `accounts` | Array<[`AuthAccount`](#authaccount)> | No | No | — |

### AuthUser

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `id` | string | No | No | — |
| `name` | string | No | No | — |
| `email` | string (email) | No | No | — |
| `telephone` | string | No | Yes | — |
| `government_id` | string | No | Yes | — |
| `is_email_verified` | boolean | No | No | — |
| `has_accepted_terms` | boolean | No | No | — |
| `created_at` | string (date-time) | No | No | — |
| `to_be_deleted_at` | string (date-time) | No | Yes | — |

### CostEstimate

Cost breakdown for an assignment plus current account balances.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `documents` | integer | No | No | Documents consumed (always 1). |
| `credits` | number | No | No | Total notification credits needed. |
| `needs_extra_document` | boolean | No | No | True when the plan's document allowance is exhausted and an extra document will be charged from credits. |
| `extra_document_cost` | number | No | No | Credits charged for the extra document when `needs_extra_document` is true. |
| `total_credits` | number | No | No | — |
| `breakdown` | Array<[`CostEstimateBreakdownItem`](#costestimatebreakdownitem)> | No | No | — |
| `document_balance` | number | No | No | — |
| `credit_balance` | number | No | No | — |
| `has_sufficient_resources` | boolean | No | No | — |
| `blocking_reason` | string | No | Yes | enum: `"PendingPayment"`, `"InsufficientDocuments"`, `"InsufficientCredits"` |
| `message` | string | No | Yes | — |

### CostEstimateBreakdownItem

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `code` | string | No | No | — |
| `name` | string | No | No | — |
| `cost` | number | No | No | — |
| `quantity` | integer | No | No | — |
| `unit_cost` | number | No | No | — |

### DisplaySettings

A field placement rectangle on a document page. Geometry values are pixels in Assinafy's 150-DPI page image, measured from the upper-left corner. Clients must keep the rectangle within the selected page's width and height; the API does not clamp out-of-bounds values.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `left` | number (float) | Yes | No | Horizontal distance from the page's left edge, in page-image pixels.; minimum: `0` |
| `top` | number (float) | Yes | No | Vertical distance from the page's top edge, in page-image pixels.; minimum: `0` |
| `width` | number (float) | Yes | No | Width of the placement rectangle, in page-image pixels.; minimum: `0` |
| `height` | number (float) | Yes | No | Height of the placement rectangle, in page-image pixels.; minimum: `0` |
| `fontFamily` | string | No | No | Font-family presentation metadata. |
| `fontSize` | number (float) | Yes | No | Font size in the 150-DPI page-image coordinate system.; minimum: `0` |
| `backgroundColor` | string | No | No | CSS-compatible background-color presentation metadata. |

### Document

A document and its current lifecycle state.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `resource` | string | No | No | Present in single-resource responses. |
| `id` | string | No | No | — |
| `account_id` | string | No | No | — |
| `template_id` | string | No | Yes | — |
| `name` | string | No | No | — |
| `status` | string | No | No | Status code — see GET /v1/documents/statuses. |
| `artifacts` | object | No | No | Artifact download URLs keyed by name (original, certificated, certificate-page, bundle). |
| `is_closed` | boolean | No | No | — |
| `signing_url` | string | No | No | — |
| `decline_reason` | string | No | Yes | — |
| `declined_by` | [`Signer`](#signer) | No | Yes | — |
| `tags` | Array<object { `id`: string; `name`: string }> | No | No | — |
| `assignment` | [`Assignment`](#assignment) | No | Yes | Expanded assignment data when included via ?expand=assignment; null otherwise. |
| `pages` | Array<[`DocumentPage`](#documentpage)> | No | No | — |
| `created_at` | string (date-time) | No | No | — |
| `updated_at` | string (date-time) | No | No | — |

### DocumentActivity

A document activity event.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `id` | integer | No | No | — |
| `event` | string | No | No | Event type code. |
| `message` | string | No | No | — |
| `payload` | object | No | Yes | Event-specific payload state. Keys vary per event. |
| `origin` | object { `ip`: string; `user-agent`: string } | No | Yes | Request origin when available. |
| `created_at` | string (date-time) | No | No | — |

### DocumentPage

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `id` | string | No | No | — |
| `number` | integer | No | No | — |
| `height` | integer | No | No | — |
| `width` | integer | No | No | — |
| `download_url` | string | No | No | — |

### DocumentStatsRow

One period of the document-funnel KPI series. `period` is `YYYY-MM` (monthly) or `YYYY-MM-DD` (daily); series are zero-filled, no gaps. Signature requests come with two independent breakdowns: the `signature_requests_notification_*` counters split them by the channels the signer was notified on — a signer reached on more than one channel counts once per channel, so these add up to at least `signature_requests` — while the `signature_requests_verification_*` counters split them by how the signer's identity is verified, and since each request has exactly one verification method those four always add up to `signature_requests`.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `period` | string | No | No | `YYYY-MM` (monthly) or `YYYY-MM-DD` (daily). |
| `documents_uploaded` | integer | No | No | — |
| `documents_sent` | integer | No | No | — |
| `signature_requests` | integer | No | No | — |
| `signature_requests_notification_email` | integer | No | No | Requests notified by e-mail. |
| `signature_requests_notification_whatsapp` | integer | No | No | Requests notified by WhatsApp. |
| `signature_requests_notification_bypass` | integer | No | No | Requests with no notification sent (`Bypass`). |
| `signature_requests_verification_email` | integer | No | No | Requests verified by an e-mail token. |
| `signature_requests_verification_whatsapp` | integer | No | No | Requests verified by a WhatsApp token. |
| `signature_requests_verification_bypass` | integer | No | No | Requests signed without token verification (`Bypass`). |
| `signature_requests_verification_digital_certificate` | integer | No | No | Requests signed with the signer's own ICP-Brasil digital certificate. |
| `signature_requests_viewed` | integer | No | No | Signature requests whose document was first viewed during the period. |
| `signature_requests_completed` | integer | No | No | Signature requests completed by individual signers during the period. |
| `documents_certified` | integer | No | No | — |

### DocumentStatus

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `code` | string | No | No | — |
| `deletable` | boolean | No | No | — |

### DocumentVerification

The verification result for a document looked up by signature hash. When not verified, most fields are null and `is_valid` is false.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `hash` | string | No | No | — |
| `id` | string | No | Yes | — |
| `status` | string | No | Yes | — |
| `page_count` | string | No | Yes | — |
| `signer_count` | string | No | Yes | — |
| `completed_count` | integer | No | Yes | — |
| `completed_at` | string (date-time) | No | Yes | — |
| `verified_at` | string (date-time) | No | No | — |
| `is_valid` | boolean | No | No | — |
| `message` | string | No | No | Reason when not valid. |

### Envelope

Standard success wrapper. Operations add their own `data`.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `status` | integer | No | No | HTTP status code, mirrored in the body. |
| `message` | string | No | No | Human-readable message; empty on success. |

### ErrorEnvelope

Standard error wrapper. `status` mirrors the HTTP status code.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `status` | integer | No | No | — |
| `message` | string | No | No | Human-readable error message. |
| `data` | object | No | Yes | — |

### Field

A reusable field definition.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `resource` | string | No | No | — |
| `id` | string | No | No | — |
| `name` | string | No | No | — |
| `type` | string | No | No | — |
| `regex` | string | No | Yes | — |
| `is_pre_defined` | boolean | No | No | — |
| `is_active` | boolean | No | No | — |
| `is_required` | boolean | No | No | — |
| `is_standard` | boolean | No | No | — |
| `is_read_only` | boolean | No | No | — |
| `is_visible` | boolean | No | No | — |

### FieldType

A supported field/validation type.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `type` | string | No | No | — |
| `name` | string | No | No | — |

### FieldValidation

The result of validating a value against a field definition.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `type` | string | No | No | The field's validation type. |
| `success` | boolean | No | No | — |
| `error_message` | string | No | No | Empty when valid. |

### FieldValidationResult

A per-field result from a multi-field validation.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `field_id` | string | No | No | — |
| `type` | string | No | No | — |
| `success` | boolean | No | No | — |
| `error_message` | string | No | No | — |

### NotificationHistoryEntry

A single notification delivery record for a signer channel.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `event` | string | No | No | — |
| `status` | string | No | No | enum: `"sent"`, `"failed"` |
| `error_code` | string | No | Yes | — |
| `error_message` | string | No | Yes | — |
| `sent_at` | string (date-time) | No | Yes | — |
| `failed_at` | string (date-time) | No | Yes | — |

### NotificationPreferences

Owner-facing document notifications, keyed by notification type. `true` means the e-mail is sent.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `DocumentCompleted` | boolean | No | No | Every signer has signed and the document is certified. |
| `SignerDeclined` | boolean | No | No | A signer declined to sign. |
| `DocumentCancelled` | boolean | No | No | The document was cancelled. |
| `DocumentAboutToExpire` | boolean | No | No | The signature deadline is approaching. |
| `DocumentExpired` | boolean | No | No | The signature deadline passed. |
| `DocumentExpirationReset` | boolean | No | No | The signature deadline was extended. |
| `DocumentProcessingFailed` | boolean | No | No | An uploaded document could not be processed. |
| `TemplateProcessingFailed` | boolean | No | No | A template could not be processed. |
| `SignerWhatsappFailed` | boolean | No | No | A WhatsApp notification to a signer could not be delivered. |

### Signer

A signing party belonging to a workspace account.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `resource` | string | No | No | Present in single-resource responses. |
| `id` | string | No | No | — |
| `full_name` | string | No | No | — |
| `email` | string (email) | No | Yes | — |
| `whatsapp_phone_number` | string | No | Yes | E.164 format; normalized on save. |
| `has_accepted_terms` | boolean | No | No | — |

### SignerSelf

The current signer, as returned by `GET /v1/signers/self`. Extends Signer with the signature-state flags that are only computed for the authenticated signer.

Type: [`Signer`](#signer) plus object { `has_signature`: boolean; `has_initial`: boolean; `is_signature_reusable`: boolean }.

### SigningUrl

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `signer_id` | string | No | No | — |
| `url` | string | No | No | — |

### Tag

A workspace-scoped label. Names are unique per workspace (case-insensitive).

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `resource` | string | No | No | — |
| `id` | string | No | No | — |
| `name` | string | No | No | — |
| `color` | string | No | Yes | 6-char hex without leading #. |
| `created_at` | string (date-time) | No | No | — |
| `updated_at` | string (date-time) | No | No | — |

### Template

A reusable document template.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `resource` | string | No | No | — |
| `id` | string | No | No | — |
| `name` | string | No | No | — |
| `document_name` | string | No | Yes | Default name for documents created from this template. |
| `message` | string | No | Yes | Default invitation message. |
| `status` | string | No | No | One of uploading, uploaded, processing, ready, failed. |
| `pages` | Array<[`TemplatePage`](#templatepage)> | No | No | — |
| `roles` | Array<[`TemplateRole`](#templaterole)> | No | No | — |
| `tags` | Array<object { `id`: string; `name`: string }> | No | No | — |
| `default_document_tags` | Array<object { `id`: string; `name`: string }> | No | No | Applied to documents created from this template; only returned by the single-template endpoint. |
| `created_at` | string (date-time) | No | No | — |
| `updated_at` | string (date-time) | No | No | — |

### TemplateFieldPlacement

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `id` | string | No | No | — |
| `field_id` | string | No | No | — |
| `role_id` | string | No | No | — |
| `label` | string | No | No | — |
| `display_settings` | object | No | No | Rendering metadata for the placement. |
| `created_at` | string (date-time) | No | No | — |
| `updated_at` | string (date-time) | No | No | — |

### TemplatePage

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `id` | string | No | No | — |
| `number` | integer | No | No | — |
| `height` | integer | No | No | — |
| `width` | integer | No | No | — |
| `download_url` | string | No | No | — |
| `fields` | Array<[`TemplateFieldPlacement`](#templatefieldplacement)> | No | No | — |

### TemplateRole

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `id` | string | No | No | — |
| `name` | string | No | No | — |
| `assignment_type` | string | No | No | — |
| `created_at` | string (date-time) | No | No | — |
| `updated_at` | string (date-time) | No | No | — |

### WebhookDispatch

A single webhook delivery-history entry.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `resource` | string | No | No | Always `activity_dispatching_history` in single-resource responses. |
| `id` | string | No | No | Dispatch entry ID. |
| `event` | string | No | No | Event type that triggered the dispatch. |
| `activity_id` | integer | No | No | Internal activity ID associated with the dispatch. |
| `endpoint` | string | No | Yes | URL that received the request. |
| `payload` | object | No | Yes | JSON payload sent to the endpoint. |
| `delivered` | boolean | No | No | Whether delivery succeeded. |
| `http_status` | integer | No | Yes | HTTP status returned (null if connection failed). |
| `response_body` | string | No | Yes | Endpoint response body, truncated to 2000 chars. |
| `error` | string | No | Yes | Delivery error message, if any. |
| `created_at` | string (date-time) | No | No | — |
| `updated_at` | string (date-time) | No | No | — |

### WebhookEventType

A subscribable webhook event type.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `id` | string | No | No | Event type code. |
| `description` | string | No | No | When the event is triggered. |

### WebhookSubscription

An account's webhook subscription configuration.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `events` | Array<string> | No | No | Event types subscribed for delivery. |
| `is_active` | boolean | No | No | Whether webhook delivery is active. |
| `url` | string | No | Yes | Webhook endpoint URL. |
| `email` | string | No | Yes | Contact email for delivery notices. |
| `updated_at` | string (date-time) | No | Yes | — |

### WhatsappNotification

A rendered WhatsApp notification sent for an assignment, split into header/body/buttons as the signer would see them.

| Property | Type | Required | Nullable | Constraints / description |
| --- | --- | --- | --- | --- |
| `sent_at` | integer | No | No | Unix timestamp when sent. |
| `header` | string | No | No | — |
| `body` | string | No | No | — |
| `buttons` | Array<object { `text`: string }> | No | No | — |
| `phone_number` | string | No | No | Recipient phone (E.164). |
| `signer_id` | string | No | No | — |
