# Assinafy Ruby SDK

*[Leia em português](README.md) · English*

[![CI](https://github.com/assinafy/ruby-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/assinafy/ruby-sdk/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/assinafy.svg)](https://rubygems.org/gems/assinafy)

Ruby SDK for the [Assinafy API v1](https://api.assinafy.com.br/v1/docs).

The SDK exposes every Assinafy API v1 operation — including OAuth 2.1, two-factor authentication, webhook
endpoints with native signatures, and the complete supported template lifecycle. The checked-in
[`spec/api_coverage_spec.rb`](spec/api_coverage_spec.rb) validates that each route maps uniquely to a public SDK
method.

- **Source:** <https://github.com/assinafy/ruby-sdk>
- **Issues:** <https://github.com/assinafy/ruby-sdk/issues>
- **API docs:** <https://api.assinafy.com.br/v1/docs>
- **Ruby SDK API reference:** [`docs/API_REFERENCE.md`](docs/API_REFERENCE.md)

This guide follows an integration end to end — [install and configure](#installation-and-configuration),
[authenticate](#authentication), [connect over OAuth](#oauth-21), then the
[complete document workflow](#complete-document-workflow) — and ends with a
[per-resource reference](#resource-reference).

## Installation and configuration

Requirements: Ruby 3.2+ (maintained support: 3.3+; 3.2 is legacy/EOL compatibility), Bundler, and TLS 1.2 or
newer (the SDK refuses TLS 1.0 and 1.1).

```ruby
gem 'assinafy'
```

```bash
bundle install
```

From GitHub Packages (mirror), with a personal access token that has the `read:packages` scope:

```ruby
source 'https://rubygems.pkg.github.com/assinafy' do
  gem 'assinafy'
end
```

```bash
bundle config https://rubygems.pkg.github.com/assinafy USERNAME:TOKEN
```

### Environments

| Environment | `base_url` | OAuth authorization server |
| --- | --- | --- |
| Production | `https://api.assinafy.com.br/v1` (default) | `https://auth.assinafy.com.br` |
| Sandbox | `https://sandbox.assinafy.com.br/v1` | `https://auth-sandbox.assinafy.com.br` |

The sandbox is free: use it to test an integration before production by changing `base_url` and, for OAuth, the
authorization server. Never send sandbox API keys to production or the reverse. Webhook endpoints and two-factor
authentication are available in production (`api.assinafy.com.br`).

### Configuration

```ruby
require 'logger'
client = Assinafy::Client.new(
  api_key:        ENV.fetch('ASSINAFY_API_KEY'),
  account_id:     ENV.fetch('ASSINAFY_ACCOUNT_ID'),
  base_url:       ENV.fetch('ASSINAFY_BASE_URL', 'https://api.assinafy.com.br/v1'),
  webhook_secret: ENV['ASSINAFY_WEBHOOK_SECRET'],   # the endpoint's whsec_... secret
  timeout:        30,
  logger:         Logger.new($stdout)
)
```

- `base_url:` must be an absolute `http`/`https` URL. Anything else — a scheme-less host, a relative path, or
  another scheme — raises `Assinafy::ValidationError` instead of attaching your credentials to it. A trailing
  slash is stripped. `Configuration#base_url=` and `#timeout=` validate the same way as the constructor.
- Account-scoped methods accept a per-call account override for multi-workspace tenants.
- `logger:` receives SDK lifecycle messages, never request bodies or credentials.
- Every request sends `User-Agent: Assinafy-Ruby-SDK/v<Assinafy::VERSION>`.
- `Client.from_config(hash)` accepts string- or symbol-keyed hashes (e.g. parsed YAML).

## Authentication

| Credential | Who acts | Use for |
| --- | --- | --- |
| **API key** (`api_key:`) | the workspace | back-end integrations. Permanent. Sent as `X-Api-Key`. |
| **Session token** (`token:`) | the logged-in user | after `client.auth.login`. A JWT that expires in about an hour. |
| **OAuth 2.1** (`token:`) | an app, **on behalf of** a user | marketplace apps, third-party integrations, AI assistants. See [OAuth 2.1](#oauth-21). |

Configure exactly one credential per client; if both are supplied, the SDK sends only `X-Api-Key`. A client with
no credentials serves login, OAuth, and public or signer endpoints — the SDK strips `X-Api-Key`/`Authorization`
from those calls regardless.

### Login, with the two-factor challenge

```ruby
public_client = Assinafy::Client.new
session = public_client.auth.login(email: 'user@example.com', password: ENV.fetch('ASSINAFY_PASSWORD'))

if session['mfa_token']
  session = public_client.auth.verify_mfa(
    mfa_token: session['mfa_token'],
    code:      '123456'            # or a recovery code such as "ABCD-EFGH-JKMN"
  )
end

user_client = Assinafy::Client.new(
  token:      session.fetch('access_token'),
  account_id: session.fetch('accounts').first.fetch('id')
)
```

When the user has two-factor authentication enabled, `login` answers with an `mfa_token` challenge instead of an
access token. `verify_mfa` is sent without workspace credentials. The challenge is single-use and expires 5 minutes
after login; a wrong code answers `400`, and an expired, used, or over-attempted challenge answers `401` — log in
again. `social_login` returns the same shape.

### Managing two-factor authentication

```ruby
enrollment = user_client.auth.start_totp_enrollment(label: 'My phone')
enrollment['provisioning_uri']  # => "otpauth://totp/...": render as a QR code
enrollment['secret']            # returned only by this call

codes = user_client.auth.confirm_totp_enrollment(method_id: enrollment.fetch('id'), code: '123456')
codes['recovery_codes']         # => ["ABCD-EFGH-JKMN", ...] — shown only once

user_client.auth.mfa_methods
# => { 'methods' => [{ 'id' => 'mfa-method-id', 'type' => 'Totp', 'label' => 'My phone', ... }],
#      'recovery_codes_remaining' => 10 }

user_client.auth.regenerate_recovery_codes(password: ENV.fetch('ASSINAFY_PASSWORD'))
user_client.auth.delete_mfa_method('mfa-method-id', code: '123456')  # => { 'is_mfa_enabled' => false }
```

- Two-factor authentication stays off until `confirm_totp_enrollment` succeeds.
- Confirming a new authenticator while one is already confirmed **replaces** it and requires re-authentication
  with `password:` or `reauth_code:` (a code from the current device, or a recovery code).
- `regenerate_recovery_codes` and `delete_mfa_method` require `password:` or `code:`; with neither, the SDK raises
  `ValidationError` before sending. A recovery code used as proof is consumed. Removing the last method also
  discards the recovery codes.

### API keys and passwords

```ruby
client.auth.create_api_key(password: 'secret')   # shown once; replaces the previous key
client.auth.get_api_key                          # masked
client.auth.delete_api_key
client.auth.social_login(provider: 'google', token: 'id-token', has_accepted_terms: true)
client.auth.link_social_login(provider: 'google', token: 'id-token')
client.auth.change_password(email: 'user@example.com', password: 'old', new_password: 'new')
client.auth.request_password_reset(email: 'user@example.com')
client.auth.reset_password(email: 'user@example.com', new_password: 'new', token: 'reset-token')
```

## OAuth 2.1

Use OAuth when an application acts **on behalf of a user**, with that user's permission. Unlike an API key, the
token is scoped to one workspace and carries only the scopes the user approved. It never reaches billing, account
lifecycle, credential management, webhook signing secrets, or admin surfaces, whatever scopes it holds.

The flow is authorization-code with **mandatory PKCE**; the authorization server accepts `S256` only.

| Scope | Grants |
| --- | --- |
| `documents:read` | Read documents, pages, tags, signers, assignments, activity, webhook deliveries |
| `documents:write` | Create, update, delete documents and manage their signers and assignments |
| `templates:read` | Read templates, pages, roles, fields, tags |
| `templates:write` | Create, update, delete templates |
| `account:read` | Read the workspace profile, theme, logo, webhook endpoints |
| `webhooks:write` | Create, change, deactivate, and delete the workspace's webhook endpoints |
| `openid` | Identify the user (`sub` claim) and enable `/oauth/userinfo` |
| `profile` | Include the user's name in the claims |
| `email` | Include the user's email and verification status in the claims |
| `offline_access` | Be issued a refresh token (never echoed in the returned `scope`) |

**1. Register a callback and redirect the user.** Register an HTTPS callback URL in the Assinafy application.
For each authorization attempt, store the verifier, the state, and the expected issuer:

```ruby
verifier = Assinafy::OAuth.generate_code_verifier
state    = Assinafy::OAuth.generate_state

session[:assinafy_code_verifier] = verifier
session[:assinafy_state]         = state
session[:assinafy_issuer]        = Assinafy::OAuth::AUTHORIZATION_SERVER # issuer of the server this attempt uses

redirect_to Assinafy::OAuth.authorization_url(
  client_id:     ENV.fetch('ASSINAFY_CLIENT_ID'),
  redirect_uri:  'https://app.example.com/oauth/callback',
  code_verifier: verifier,
  state:         state,
  scope:         %w[documents:read documents:write offline_access]
)
```

The `code_challenge` is derived from the verifier; the verifier itself never appears in the URL.
`Assinafy::OAuth::AUTHORIZATION_SERVER` is the production issuer. For the sandbox, pass
`authorization_endpoint: 'https://auth-sandbox.assinafy.com.br/oauth/authorize'` and store
`https://auth-sandbox.assinafy.com.br` instead.

**2. Validate the callback and exchange the code.** Check `state` and `iss` against the values stored for this
attempt before anything else, including on an `error=` return — that is the CSRF check, and it rejects responses
that are not yours. The code is single-use and expires 60 seconds after approval: exchange it at once, with the
same `redirect_uri`, and never retry.

```ruby
unless params[:state] == session.delete(:assinafy_state) &&
       params[:iss] == session.delete(:assinafy_issuer)
  raise 'authorization response is not ours'
end
raise "authorization not granted: #{params[:error]}" if params[:error] # access_denied, invalid_scope, ...

tokens = Assinafy::Client.new.oauth.exchange_code(
  code:          params.fetch(:code),
  client_id:     ENV.fetch('ASSINAFY_CLIENT_ID'),
  code_verifier: session.delete(:assinafy_code_verifier),
  redirect_uri:  'https://app.example.com/oauth/callback'
)
# => { 'access_token' => ..., 'token_type' => 'Bearer', 'expires_in' => 3600,
#      'refresh_token' => ..., 'scope' => 'documents:read documents:write' }
```

The SDK checks the `code_verifier` grammar locally, because the server reports a malformed verifier as
`invalid_grant` — indistinguishable from an expired code.

**3. Persist the connection and act as the user.** The token works only in the workspace the user picked.

```ruby
access_token = tokens.fetch('access_token')
workspace_id = Assinafy::Client.new(token: access_token).accounts.list[:data].first.fetch('id')

connection = Connection.create!(
  workspace_id:  workspace_id,
  scope:         tokens.fetch('scope'),
  access_token:  access_token,               # store encrypted
  refresh_token: tokens['refresh_token'],    # store encrypted
  expires_at:    Time.now + tokens.fetch('expires_in')
)

user_client = Assinafy::Client.new(token: connection.access_token, account_id: connection.workspace_id)
user_client.documents.list
user_client.oauth.userinfo  # => { 'sub' => ..., 'name' => ..., 'email' => ... } (openid scope)
```

**4. Refresh with rotation, one at a time per connection.** Every refresh returns a **new** refresh token, valid
for another 30 days, and retires the old one, so a connection only expires after 30 days without a refresh.
Reusing a retired refresh token ends the whole connection, so refresh under a per-connection lock and store the
new tokens atomically before using them:

```ruby
connection.with_lock do                          # row lock: one refresh at a time per connection
  next if connection.expires_at > Time.now + 60  # another worker already refreshed

  tokens = Assinafy::Client.new.oauth.refresh(
    refresh_token: connection.refresh_token,
    client_id:     ENV.fetch('ASSINAFY_CLIENT_ID')
  )

  connection.update!(
    refresh_token: tokens.fetch('refresh_token'),
    access_token:  tokens.fetch('access_token'),
    expires_at:    Time.now + tokens.fetch('expires_in')
  )
end
user_client = Assinafy::Client.new(token: connection.access_token, account_id: connection.workspace_id)
```

> The SDK does **not** refresh automatically and sends each token request once — never add retry middleware to
> the connection. `refresh` raises `Assinafy::Error` rather than return a success without a new refresh token;
> handle it like `invalid_grant`.
>
> If a refresh fails without a clear answer — a timeout, a reset connection, a `5xx` — the server may have rotated
> the token without the response reaching you. Re-read the stored refresh token: if it is still the one you sent,
> **never send it again**; ask the user to connect again. Carry on only if another worker has since stored a
> different one. Only a failure that provably happened before the request was sent — DNS resolution, a refused
> connection, a failed TLS handshake — is safe to retry. On an API `401`, refresh once; if that fails, or on
> `invalid_grant`, ask the user to connect again.

A refresh token exists only when `offline_access` was requested *and* consented.

**5. Revoke on disconnect.** Revoke the refresh token in storage **now** — the latest one — then delete the stored
tokens:

```ruby
Assinafy::Client.new.oauth.revoke(
  token:           connection.reload.refresh_token,
  client_id:       ENV.fetch('ASSINAFY_CLIENT_ID'),
  token_type_hint: 'refresh_token'
)
connection.destroy!
```

Revoking a refresh token also invalidates the access tokens issued from it. Every revoke outcome returns `200` —
including an unknown, already-revoked, or rotated token — so revoking a stale copy can look successful while the
connection stays active.

**Discovery**, instead of hardcoding endpoints:

```ruby
client.oauth.protected_resource_metadata['authorization_servers']
# => ["https://auth.assinafy.com.br"]

client.oauth.authorization_server_metadata['code_challenge_methods_supported']
# => ["S256"]
```

`authorization_server_metadata` reaches a different host, so — like `/oauth/token` and `/oauth/revoke` — the SDK
sends it with no workspace credentials attached. An override URL must be an absolute HTTPS URL; anything else
raises `ValidationError`.

**Internal service clients.** The advertised RFC 8693 token-exchange grant is restricted to
Assinafy-provisioned confidential service clients. Marketplace apps use PKCE authorization code
and refresh. `client.oauth.token` accepts token exchange with `client_secret`, `subject_token`,
`subject_token_type`, and `resource`; it issues no refresh token.

**Errors.** OAuth routes answer with the flat RFC 6749 object rather than this API's envelope, so the SDK raises
`Assinafy::OAuthError` (a subclass of `Assinafy::ApiError`):

```ruby
rescue Assinafy::OAuthError => e
  e.error             # => "invalid_grant"
  e.error_description # => "The authorization code is invalid or has expired."
  e.context[:www_authenticate] # on a 403, names the missing scope
```

Any resource, not only these routes, puts that challenge in `context[:www_authenticate]`. Treat it as a prompt to
reconnect with that scope added, not as a retry; a `403` without it means another workspace, the user's role, or
an area OAuth tokens never reach.

## Complete document workflow

Every call below returns the SDK value after response-envelope handling. Use the
[API operation table](docs/API_REFERENCE.md#api-operations) for each method's exact HTTP authentication,
parameters, request body, and success wire response.

### 1. Upload a document and wait for its metadata

```ruby
document = client.documents.upload({ file_path: './customer-agreement.pdf' })
document['name']   # => "customer-agreement.pdf"

document = client.documents.wait_until_ready(
  document.fetch('id'),
  max_wait_seconds:      60,
  poll_interval_seconds: 2
)
# => Document with a ready status and populated pages
```

The document is named after the uploaded file; rename it with `client.documents.rename(id, 'New name')`. For
in-memory data, pass `{ buffer: pdf_bytes, file_name: 'contract.pdf' }`. PDF only, at most 25 MB: the SDK checks
the extension, size, and `%PDF-` header before sending. `wait_until_ready` raises `Assinafy::ValidationError` for
invalid interval values and `Assinafy::Error` for a failed terminal status or a timeout.

**Or select a template.** A template upload initially contains an `Editor` role. Configure at least one `Signer`
role and its fields in the Assinafy application before generating a document. Template uploads have the same
25 MB limit as documents.

```ruby
template = client.templates.get('template-id')
```

### 2. Create or reuse signers

```ruby
signer = client.signers.find_by_email('signer@example.com') ||
         client.signers.create(full_name: 'Example Signer', email: 'signer@example.com')

# A DigitalCertificate signer needs a CPF or CNPJ in government_id — set it at creation:
cert_signer = client.signers.create(
  full_name:     'Certificate Signer',
  email:         'cert-signer@example.com',
  government_id: ENV.fetch('ASSINAFY_SIGNER_GOVERNMENT_ID')
)
# ...or later: client.signers.update(signer['id'], government_id: '...')
```

### 3. Choose verification and notification methods

Each assignment signer has a **verification method** (how they prove identity before signing) and a
**notification method** (how they receive the invitation). The two are **coupled**: send one, both, or neither —
the missing side is inferred from the other, and when both are omitted both default to `Email`.

| Verification | How it works | Allowed notification | Cost per signer |
| --- | --- | --- | --- |
| `Email` *(default)* | One-time code (OTP) by email before signing | `Email` | 0 credits |
| `Whatsapp` | One-time code (OTP) over WhatsApp; needs `whatsapp_phone_number` and a paid plan | `Whatsapp` | 0.45 credits (the WhatsApp notification) |
| `DigitalCertificate` | Signs with their own ICP-Brasil certificate (A1/A3), producing a qualified PAdES signature | `Email` **or** `Whatsapp` | 0.5 credits + its notification (0 or 0.45) |

- Send exactly one channel in `notification_methods` (a one-element array).
- The certificate charge appears in the cost breakdown under the code `SignatureDigitalCertificate`. Resending a
  notification charges the notification again.
- `DigitalCertificate` needs the Digital Certificate account feature (Standard and Pro plans), a CPF or CNPJ in the
  signer's `government_id`, and the signer alone in its signing step. A CPF requires that person's certificate (an
  e-CPF, or an e-CNPJ naming them as legal representative); a CNPJ requires an e-CNPJ for that company, from any of
  its representatives.
- `AssignmentResource::VERIFICATION_METHODS` and `::NOTIFICATION_METHODS` publish the enums. `build_payload`
  validates values, pairings, and `step` locally, so a typo fails before the request is sent.

### 4. Estimate the cost

```ruby
estimate = client.assignments.estimate_cost(
  document.fetch('id'),
  signers: [
    { verification_method: 'Email' },
    { verification_method: 'DigitalCertificate', notification_methods: ['Whatsapp'] }
  ]
)
estimate['total_credits']            # => 0.95
estimate['breakdown']                # [{ 'code' => ..., 'quantity' => ..., 'unit_cost' => ..., 'cost' => ... }]
estimate['has_sufficient_resources'] # => true
```

Estimates accept signers described by method alone, without an `id`.

### 5. Create the assignment

```ruby
assignment = client.assignments.create(
  document.fetch('id'),
  method:     'virtual',
  signers:    [
    { id: signer.fetch('id'),      verification_method: 'Email', notification_methods: ['Email'], step: 1 },
    { id: cert_signer.fetch('id'), verification_method: 'DigitalCertificate', notification_methods: ['Email'], step: 2 }
  ],
  message:    'Please review and sign.',
  expires_at: '2099-12-31T23:59:00Z'
)
assignment['signing_urls'] # => [{ 'signer_id' => 'signer-id', 'url' => 'https://.../sign/...' }, ...]
```

`virtual` has no positioned fields; `collect` adds `entries` of positioned fields (see
[Assignments](#assignments)). Both require a non-empty `signers` array. Steps are all-or-none, positive, and
contiguous from 1; equal steps sign in parallel, and each step is notified when the previous one finishes. A
certificate signer is alone in its step. Deadlines are zoned ISO 8601 and at least one hour ahead.

For a template, bind one distinct existing signer to each role and create the document and assignment together:

```ruby
role_signer = {
  role_id:              template.fetch('roles').find { |role| role['assignment_type'] == 'Signer' }.fetch('id'),
  id:                   signer.fetch('id'),
  verification_method:  'Email',
  notification_methods: ['Email']
}

client.documents.estimate_cost_from_template(template.fetch('id'), [role_signer])
template_document = client.documents.create_from_template(
  template.fetch('id'), [role_signer],
  name: 'customer-agreement.pdf', message: 'Please review and sign.'
)
```

**Shortcut.** `Client#upload_and_request_signatures` bundles upload, waiting, signer creation (including
`government_id`), and a virtual assignment, validating the whole payload before anything is uploaded:

```ruby
result = client.upload_and_request_signatures(
  source:     { file_path: './contract.pdf' },
  signers:    [{ full_name: 'Alice Silva', email: 'alice@example.com' }],
  message:    'Please sign.',
  expires_at: '2099-12-31T23:59:00Z'
)
result[:document]['id']   # => "document-id"
result[:signer_ids]       # => ["signer-id"]
```

It is not transactional: on a later failure, `e.context[:document]` and `e.context[:signer_ids]` list what was
created so you can clean up.

### 6. The signer experience

The signer receives an access link through the notification channel. Signer-facing calls use the one-time
`signer-access-code` (a query parameter), not workspace credentials.

```ruby
signing = Assinafy::Client.new(base_url: ENV.fetch('ASSINAFY_BASE_URL'))
access_code = ENV.fetch('ASSINAFY_SIGNER_ACCESS_CODE')

signer_data = signing.signers.self_data(signer_access_code: access_code)
signing.signers.accept_terms(signer_access_code: access_code) unless signer_data['has_accepted_terms']

signing_document = signing.assignments.signer_document(signer_access_code: access_code, has_accepted_terms: true)
signing.signers.confirm_data(
  signing_document.fetch('id'), { full_name: 'Example Signer', government_id: '00000000000' },
  signer_access_code: access_code
)
signing.signers.verify_email(                      # the OTP from email or WhatsApp
  verification_code:  ENV.fetch('ASSINAFY_VERIFICATION_CODE'),
  signer_access_code: access_code
)
signing.signers.upload_signature(File.binread('signature.png'), signer_access_code: access_code, type: 'signature')

signing.signer_documents.sign_multiple([signing_document.fetch('id')], signer_access_code: access_code)
```

That signs a virtual assignment. For a collect assignment, submit each positioned item through
`assignments.sign`; the SDK maps the snake_case item keys to the API's camelCase request keys:

```ruby
collect_items = signing_document.fetch('assignment').fetch('items').map do |item|
  { item_id: item.fetch('id'), field_id: item.dig('field', 'id'), page_id: item.dig('page', 'id'), value: 'Accepted' }
end

signing.assignments.sign(
  signing_document.fetch('id'), signing_document.dig('assignment', 'id'), collect_items,
  signer_access_code: access_code
)

# To decline instead:
signing.assignments.decline(
  signing_document.fetch('id'), signing_document.dig('assignment', 'id'),
  decline_reason: 'Terms differ from the proposal', signer_access_code: access_code
)
```

**A1/A3 certificate signers** complete their signature in Assinafy's hosted signing flow, opened from
`assignment['signing_urls']`: they accept the terms, confirm their data, and sign with their A1 or A3 certificate
through the Web PKI browser extension. The ordinary signing endpoint rejects certificate signers, and the SDK does
not wrap the Web PKI handshake (`/signers/certificate/start`, `/signers/certificate/complete`), whose schemas are
not part of the OpenAPI contract. Once it completes, the `pades` artifact returns the qualified signature.

### 7. Receive webhooks

An account can have 1 webhook endpoint, or up to 3 on paid plans. Each has its own distinct URL, event list, and
signing setting, and every active endpoint subscribed to an event receives it.

```ruby
client.webhooks.list_event_types   # => [{ 'id' => 'document_ready', 'description' => '...' }, ...]

endpoint = client.webhooks.create_endpoint(
  url:             'https://app.example.com/webhooks/assinafy',
  email:           'ops@example.com',          # delivery-failure notices
  events:          %w[document_ready signer_signed_document signer_rejected_document],
  name:            'ERP',
  signing_enabled: true
)
secret = client.webhooks.endpoint_secret(endpoint.fetch('id'))['secret']  # => "whsec_..."
```

- `create_endpoint` requires `url`, `email`, and `events`; `name`, `is_active` (default `true`), and
  `signing_enabled` (default `false`) are optional. Unknown keys raise `ValidationError` locally.
- Creating one past the plan limit answers `403`; a URL another endpoint already uses answers `400`.
- `update_endpoint(id, payload)` changes only the fields sent. `signing_enabled: true` creates a secret when the
  endpoint has none and keeps the current one otherwise; `false` discards it.
- `rotate_endpoint_secret(id)` returns a new secret; the old one stops working immediately.
- Reading and rotating secrets is not available to OAuth applications — use an API key or a user session token.
  Both answer `400` when signing is disabled.

**Delivery contract.** Each delivery is a `POST` with an `application/json` body and the headers `webhook-id`
(identical on every attempt of the same event to the same endpoint — deduplicate on it), `webhook-timestamp`
(Unix seconds), and, when signing is enabled, `webhook-signature`. Any `2xx` is success. Each event gets up to 2
attempts, 3 seconds apart; after 10 consecutive failed events the endpoint's deliveries pause and only a sample is
probed until one succeeds. Force a redelivery with `retry_dispatch`.

**Verifying signatures.** Signatures follow [Standard Webhooks](https://www.standardwebhooks.com): space-separated
`v1,<base64 HMAC-SHA256>` entries over `"{webhook-id}.{webhook-timestamp}.{raw body}"`, keyed with the
base64-decoded part of the secret after `whsec_`. `verify_delivery` checks them in constant time and rejects
timestamps more than 5 minutes from the local clock (`tolerance:` changes the window):

```ruby
class AssinafyWebhooksController < ActionController::API
  VERIFIER = Assinafy::Support::WebhookVerifier.new(ENV.fetch('ASSINAFY_WEBHOOK_SECRET'))

  def create
    raw_body = request.raw_post
    return head(:unauthorized) unless VERIFIER.verify_delivery(raw_body, request.headers)

    webhook_id = request.headers['webhook-id']
    return head(:ok) if AssinafyEvent.exists?(webhook_id: webhook_id)   # already processed

    event = VERIFIER.extract_event(raw_body)
    AssinafyEvent.create!(webhook_id: webhook_id, kind: VERIFIER.event_type(event), body: raw_body)
    ProcessAssinafyEventJob.perform_later(webhook_id)
    head :ok
  end
end
```

In plain Rack (Sinatra, Roda), pass the env: `VERIFIER.verify_delivery(request.body.read, request.env)` — the
`HTTP_WEBHOOK_ID` form is accepted, as is a plain Hash. `verify_delivery` returns `false` — never raises — for a
missing or malformed secret, a missing header, a wrong signature, or a stale timestamp. Always pass the **raw**
body exactly as received. `client.webhook_verifier` is a verifier built from the client's `webhook_secret`.

`extract_event` parses the body (or returns `nil`); `event_type`, `event_payload`, `event_object` (the entity acted
on), and `event_subject` (the actor) read the envelope `{ id, event, message, payload, origin, created_at,
subject, object, account_id }`. `subject` and `object` carry a `type` (`User`, `Signer`, `Account`, `Document`, or
`Template`); body timestamps are Unix seconds.

`verify(raw_body, hex_signature)` remains only for receivers whose own gateway signs bodies with a hex
HMAC-SHA256 shared secret.

### 8. Track progress, download, and verify

```ruby
document_id = document.fetch('id')

client.documents.signing_progress(document_id)  # => { signed: 1, total: 2, pending: 1, percentage: 50.0 }
client.documents.fully_signed?(document_id)
client.documents.activities(document_id)        # => Array<DocumentActivity>

signed_pdf = client.documents.download(document_id, 'certificated')
# also 'original', 'certificate-page', 'bundle' (zip), and 'pades' for certificate-signed documents

verification = client.documents.verify('signature-hash-from-assinafy')
verification['is_valid']        # => true
verification['agreement_code']  # printed on the document certificate
```

`verify` returns Assinafy's verification result. It does not independently validate the PDF signature or its
certificate chain; see [Authentication and safety](docs/API_REFERENCE.md#authentication-and-safety).

### 9. Clean up

```ruby
client.documents.delete(document_id)
client.signers.delete(signer.fetch('id'))
client.webhooks.delete_endpoint(endpoint.fetch('id'))
```

Delete only resources your application owns, after downstream work is complete; keep shared signer and template
data. Some resources return `409` while processing or while still referenced.

### 10. Handle errors

```ruby
begin
  client.documents.details(document_id)
rescue Assinafy::ValidationError => e
  warn e.errors.inspect
rescue Assinafy::ApiError => e
  warn "Assinafy returned #{e.status_code}: #{e.message}"
rescue Assinafy::NetworkError => e
  warn "Network failure: #{e.message}"
end
```

See [Errors](#errors) for the full hierarchy.

## Resource reference

`Assinafy::Client` exposes thirteen accessors — twelve API resources plus the local `webhook_verifier` helper:

| Accessor                    | What it covers                                                     |
| --------------------------- | ------------------------------------------------------------------ |
| `client.auth`               | Login, two-factor authentication, social login, passwords, API keys |
| `client.oauth`              | OAuth 2.1 token exchange, refresh, revocation, userinfo, discovery |
| `client.accounts`           | Account CRUD, theme, KPI stats, brand logo                         |
| `client.users`              | User profile, notification preferences, cross-account KPIs         |
| `client.documents`          | Upload, list, search, rename, download, delete, verify, tags       |
| `client.signers`            | Workspace signer CRUD + signer self-service endpoints              |
| `client.signer_documents`   | Signer-authenticated multi-document operations + search            |
| `client.assignments`        | List/create/sign/decline/resend/estimate assignments               |
| `client.templates`          | Template creation (file upload), get, list, update, delete         |
| `client.tags`               | Workspace tags                                                     |
| `client.fields`             | Field definitions + validation + type catalog                      |
| `client.webhooks`           | Webhook endpoints, signing secrets, event catalog, deliveries, retries |
| `client.webhook_verifier`   | Standard Webhooks signature verification for received deliveries   |

### Accounts

```ruby
client.accounts.list                                  # { data: [...] } — no pagination meta
client.accounts.get                                   # the current account (or pass an id)
client.accounts.create(name: 'Acme Inc.')
client.accounts.update({ name: 'Acme Renamed' })
client.accounts.delete(force: true, account_id_override: 'account-id')
client.accounts.theme                                 # { account_name, primary_color, secondary_color, logo }
client.accounts.stats(granularity: 'monthly', month: '2026-06')  # account KPI rows
client.accounts.upload_logo({ file_path: './logo.png' })
client.accounts.download_logo                          # raw bytes; raises ApiError on HTTP 404 when unset
client.accounts.delete_logo
```

### Users

```ruby
client.users.me
client.users.stats(granularity: 'daily', month: '2026-06')  # cross-account KPI rows
client.users.notification_preferences                 # returns all nine owner-email preferences
client.users.update_notification_preferences(SignerDeclined: false) # partial request; returns all nine
```

Both stats methods validate `granularity` (`monthly` or `daily`) and `month` (`YYYY-MM`) locally, and return rows
with `period`, `documents_uploaded`, `documents_sent`, `signature_requests`,
`signature_requests_notification_email`, `signature_requests_notification_whatsapp`,
`signature_requests_notification_bypass`, `signature_requests_verification_email`,
`signature_requests_verification_whatsapp`, `signature_requests_verification_bypass`,
`signature_requests_verification_digital_certificate`, `signature_requests_viewed`,
`signature_requests_completed`, and `documents_certified`.

### Documents

```ruby
client.documents.statuses                                    # GET /documents/statuses
client.documents.list(page: 1, per_page: 20, status: 'pending_signature')
client.documents.list(tags: ['tag-id-1', 'tag-id-2'])        # documents carrying every listed tag
client.documents.search('contract')                          # lightweight GET .../documents/search
client.documents.upload({ file_path: './contract.pdf' })     # named after the file
client.documents.upload({ buffer: pdf_bytes, file_name: 'contract.pdf' })
client.documents.rename('document-id', 'renamed.pdf')        # PATCH /documents/{id}
client.documents.get('document-id')                          # alias of .details
client.documents.wait_until_ready('document-id', max_wait_seconds: 60)
client.documents.activities('document-id')
client.documents.thumbnail('document-id')                    # binary PNG/JPEG
client.documents.download('document-id', 'certificated')     # binary PDF
client.documents.download('document-id', 'pades')            # signed PAdES artifact
client.documents.download_page('document-id', 'page-id')
client.documents.delete('document-id')
client.documents.verify('signature-hash')
client.documents.public_info('document-id')
client.documents.send_token('document-id', email: 'alice@example.com')
client.documents.list_tags('document-id')
client.documents.replace_tags('document-id', ['tag-id-1', 'tag-id-2'])
client.documents.append_tags('document-id', ['tag-id-3'])
client.documents.detach_tag('document-id', 'tag-id')

client.documents.create_from_template(
  'template-id',
  [{ role_id: 'role-id', id: 'signer-id', verification_method: 'Email', notification_methods: ['Email'] }],
  { name: 'Contract', message: 'Please sign', expires_at: '2099-12-31T23:59:00Z' }
)
client.documents.estimate_cost_from_template('template-id', [{ role_id: 'role-id', verification_method: 'Whatsapp' }])

client.documents.fully_signed?('document-id')
client.documents.signing_progress('document-id')   # => { signed: 1, total: 2, pending: 1, percentage: 50.0 }
```

An Array `tags` filter is sent as comma-separated tag IDs. The tag arrays of `replace_tags`/`append_tags` take tag
IDs.

### Signers (workspace CRUD)

```ruby
client.signers.create(full_name: 'Alice Silva', email: 'alice@example.com')
client.signers.create(full_name: 'Bob Costa',  phone: '+5500000000000')  # phone -> whatsapp_phone_number
client.signers.create(full_name: 'Carla Lima', email: 'carla@example.com', government_id: '00000000000')
client.signers.validate_create!(full_name: 'Alice Silva', email: 'alice@example.com')  # no request
client.signers.get('signer-id')
client.signers.list(search: 'alice', per_page: 50)  # returns { data:, meta: }
client.signers.update('signer-id', full_name: 'Alice S.', government_id: '00000000000')
client.signers.delete('signer-id')
client.signers.find_by_email('alice@example.com')   # case-insensitive; nil when no match
```

### Signers (self-service, signer-access-code)

```ruby
client.signers.self_data(signer_access_code: 'code') # includes has_signature, has_initial, is_signature_reusable
client.signers.accept_terms(signer_access_code: 'code')
client.signers.verify_email(verification_code: '123456', signer_access_code: 'code')
client.signers.confirm_data('document-id', { full_name: 'Alice Silva', email: 'alice@example.com', government_id: '00000000000' }, signer_access_code: 'code')
client.signers.upload_signature(png_bytes, signer_access_code: 'code', type: 'signature', content_type: 'image/png')
client.signers.download_signature(signer_access_code: 'code', type: 'signature')
```

### Assignments

```ruby
# Virtual (no positioned fields)
client.assignments.create(
  'document-id',
  method:         'virtual',
  signers:        [{ id: 'signer-1', verification_method: 'Email', notification_methods: ['Email'], step: 1 }],
  message:        'Please sign',
  expires_at:     '2099-12-31T23:59:00Z',
  copy_receivers: ['cc-signer-id']
)

# Collect (positioned fields)
client.assignments.create(
  'document-id',
  method:  'collect',
  signers: [{ id: 'signer-1' }],
  entries: [{ page_id: 'page-id', fields: [{ signer_id: 'signer-1', field_id: 'field-id',
                                             display_settings: { left: 100, top: 100, width: 240,
                                                                 height: 48, fontSize: 16 } }] }]
)

client.assignments.list                                       # GET /assignments (scoped to the account)
client.assignments.estimate_cost('document-id', signers: [{ verification_method: 'Whatsapp' }])
client.assignments.reset_expiration('document-id', 'assignment-id', '2099-12-31T23:59:00Z')
client.assignments.reset_expiration('document-id', 'assignment-id', nil) # clears the expiry
client.assignments.resend_notification('document-id', 'assignment-id', 'signer-id')
client.assignments.estimate_resend_cost('document-id', 'assignment-id', 'signer-id')
client.assignments.whatsapp_notifications('document-id', 'assignment-id')

# Signer perspective (signer-access-code authentication)
client.assignments.signer_document(signer_access_code: 'code', has_accepted_terms: true)
client.assignments.sign('document-id', 'assignment-id',
                        [{ item_id: 'i1', field_id: 'f1', page_id: 'p1', value: 'Alice' }],
                        signer_access_code: 'code')
client.assignments.decline('document-id', 'assignment-id', decline_reason: 'Clause 2', signer_access_code: 'code')
```

The `sign` body is the API's camelCase exception: the SDK maps `item_id`/`field_id`/`page_id` to
`itemId`/`fieldId`/`pageId` (camelCase input passes through). Assignment listing sends the camelCase `accountId`
query parameter.

### Signer documents (multi-document workflows)

```ruby
client.signer_documents.current('signer-id', signer_access_code: 'code')
client.signer_documents.list('signer-id', { status: 'pending_signature' }, signer_access_code: 'code')
client.signer_documents.search('signer-id', 'contract', signer_access_code: 'code')
client.signer_documents.sign_multiple(%w[document-id-1 document-id-2], signer_access_code: 'code')
client.signer_documents.decline_multiple(%w[document-id-1 document-id-2], decline_reason: 'No', signer_access_code: 'code')
client.signer_documents.download('signer-id', 'document-id', 'pades') # public: no access code needed
```

### Templates

```ruby
client.templates.list(search: 'contract', per_page: 25)
client.templates.get('template-id')
client.templates.create({ file_path: './contract.pdf' })   # multipart upload, up to 25 MB
client.templates.create({ buffer: pdf_bytes, file_name: 'contract.pdf' })
client.templates.update('template-id', name: 'Renamed template')
client.templates.delete('template-id')
client.templates.download_page('template-id', 'page-id')   # binary image bytes
```

`get`, `create`, `update`, `delete`, and `download_page` are supported by the deployed API beyond the OpenAPI
document. `create` requires a source file; the template name defaults to the file's name. Template generation
needs one entry per role, each with a distinct existing signer ID; `role_id` comes from the template's `roles`.
Cost estimation requires `role_id` but can omit the signer ID.

### Tags

```ruby
client.tags.list(search: 'contract')
client.tags.create(name: 'Contracts', color: 'ff8800')
client.tags.update('tag-id', name: 'Sales Contracts', color: nil)  # nil clears the color
client.tags.delete('tag-id')              # fails with 409 if the tag is in use
client.tags.delete('tag-id', force: true) # detaches from documents/templates first
```

### Fields

```ruby
client.fields.types                                           # GET /field-types
client.fields.list(include_inactive: true, include_standard: false)
client.fields.create(type: 'text', name: 'Internal code', regex: '/[A-Z]{3}-[0-9]{4}/')
client.fields.get('field-id')
client.fields.update('field-id', name: 'Renamed')
client.fields.delete('field-id')

client.fields.validate('field-id', 'ABC-1234')                                    # workspace user
client.fields.validate('field-id', 'ABC-1234', signer_access_code: 'code')        # signer
client.fields.validate_multiple(
  [{ field_id: 'field-id-1', value: '1' }, { field_id: 'field-id-2', value: 'value@example.com' }],
  signer_access_code: 'code'
)
```

### Webhooks

```ruby
client.webhooks.list_event_types                              # GET /webhooks/event-types
client.webhooks.list_endpoints                                # oldest first
client.webhooks.create_endpoint(url: 'https://example.com/webhooks/assinafy', email: 'ops@example.com',
                                events: %w[document_ready], signing_enabled: true)
client.webhooks.get_endpoint('webhook-endpoint-id')
client.webhooks.update_endpoint('webhook-endpoint-id', is_active: false)
client.webhooks.delete_endpoint('webhook-endpoint-id')       # => nil
client.webhooks.endpoint_secret('webhook-endpoint-id')       # => { 'secret' => 'whsec_...' }
client.webhooks.rotate_endpoint_secret('webhook-endpoint-id')

client.webhooks.list_dispatches(endpoint_id: 'webhook-endpoint-id', delivered: false, per_page: 50)
client.webhooks.retry_dispatch('dispatch-id')

# Subscription operations act on the account's oldest endpoint:
client.webhooks.get                                           # nil on 404
client.webhooks.register(url: 'https://example.com/webhooks/assinafy', email: 'ops@example.com',
                         events: %w[document_ready signer_signed_document])
client.webhooks.inactivate                                    # stop deliveries, keep the event set
```

`register` accepts only `url`, `email`, `events`, and `is_active`; other keys raise `ValidationError`. Use the
endpoint operations for names, signing, and several endpoints.

## Responses

Most JSON successes use a `{ "status": ..., "message": ..., "data": ... }` envelope. The SDK
returns the `data` payload (a Hash for single resources, an Array for collection bodies). For
documented no-data envelopes containing only `status`/`message`, it returns `nil`; deployed API
versions that add `data` are passed through. Binary endpoints (`download`, `thumbnail`,
`download_page`, `download_signature`) return raw bytes as an ASCII-8BIT `String`, and
delete-style endpoints return `nil`.

OAuth endpoints are the exception: `/oauth/token`, `/oauth/revoke`, `/oauth/userinfo`, and the `.well-known`
metadata documents answer with flat RFC 6749 / OIDC / RFC 8615 objects rather than the envelope, and the SDK
returns those bodies unchanged.

The [SDK API reference](docs/API_REFERENCE.md) maps every API operation to its Ruby method and documents exact
authentication, parameters, request bodies, success responses, and every published schema property.

## Pagination

Most `*.list*` methods return `{ data: [...], meta: { ... } }` when the API includes pagination
headers. Ruby-style `per_page:` is transparently converted to the documented `per-page` query
parameter (values above the API's maximum are clamped server-side). Endpoints that send no pagination headers
(e.g. `accounts.list`) return `{ data: [...] }` without `meta`.

```ruby
result = client.documents.list(page: 2, per_page: 25)
result[:data] # => Array<Hash>
result[:meta] # => { current_page: 2, per_page: 25, total: 138, last_page: 6 }
```

## Errors

The SDK raises one of:

- `Assinafy::ValidationError` — caller-side input invalid (missing IDs, bad email, etc.), raised before any request.
- `Assinafy::ApiError` — the API returned a non-2xx status. Includes `status_code`, `message`, `error_name`,
  `error_code`, and `response_data`; on a `403`, `context[:www_authenticate]` names the scope an OAuth token is
  missing.
- `Assinafy::OAuthError` — an OAuth endpoint failed. Subclasses `ApiError`, and adds `error` and
  `error_description` from the flat RFC 6749 body.
- `Assinafy::NetworkError` — Faraday connection error, timeout, or TLS failure.
- `Assinafy::Error` — base class; other unexpected errors get wrapped here with the operation label.

All inherit a `#context` Hash with debugging metadata.

## Tests

```bash
bundle exec rake spec               # RSpec, including a coverage matrix
bundle exec rubocop                 # Linting
bundle exec bundler-audit check     # Dependency CVEs
ruby scripts/check_api_contract.rb --file path/to/openapi.json # validate a local contract document
```

The coverage spec validates the committed route-to-method inventory, public wrappers, aliases, and resource
mappings without network access. Ordinary pull-request CI remains network-independent; a weekly scheduled job runs
`scripts/check_api_contract.rb` against the upstream document.

### Live integration tests

The suite in [`spec/integration/`](spec/integration/live_sandbox_spec.rb) exercises safe sandbox workflows across
every workspace resource. Signer-code, OTP, password, social-login, API-key mutation, signature upload, and
irreversible sign/decline calls are wire-contract tested in the default suite but are not live-automated without
their one-time credentials or explicit state changes. The live suite is excluded from the default run and only
executes when `ASSINAFY_LIVE=1` is set with credentials:

```bash
ASSINAFY_LIVE=1 \
ASSINAFY_API_KEY=... \
ASSINAFY_ACCOUNT_ID=... \
ASSINAFY_TEST_EMAIL=recipient1@example.com \
ASSINAFY_TEST_EMAIL2=recipient2@example.com \
ASSINAFY_TEMPLATE_ID=configured-template-id \
ASSINAFY_BASE_URL=https://sandbox.assinafy.com.br/v1 \
bundle exec rspec spec/integration
```

`ASSINAFY_TEMPLATE_ID` must identify a sandbox template with a `Signer` role configured in the
application. Without it, the positive template-generation example is skipped. Supply different test
recipients for its roles. OAuth browser consent is tested separately with a registered app, an HTTPS
callback, and the matching authorization server; sandbox keys are not production OAuth credentials.

> These tests create and clean up real resources and, for the assignment flow, send real signature-request emails to the addresses in `ASSINAFY_TEST_EMAIL` / `ASSINAFY_TEST_EMAIL2`.

## Contributing

Pull requests and issues are welcome at <https://github.com/assinafy/ruby-sdk>.

## License

MIT. See [LICENSE](LICENSE).
