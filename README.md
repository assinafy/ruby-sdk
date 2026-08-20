# Assinafy Ruby SDK

[![CI](https://github.com/assinafy/ruby-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/assinafy/ruby-sdk/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/assinafy.svg)](https://rubygems.org/gems/assinafy)

Ruby SDK for the [Assinafy API v1](https://api.assinafy.com.br/v1/docs).

The SDK includes a public wrapper for every operation in the current Assinafy v1 [OpenAPI specification](https://api.assinafy.com.br/v1/docs/openapi.json), plus sandbox-live template routes that are not yet listed there. The checked-in [`spec/api_coverage_spec.rb`](spec/api_coverage_spec.rb) verifies that its static route-to-method inventory is unique and points to public SDK methods.

- **Source:** <https://github.com/assinafy/ruby-sdk>
- **Issues:** <https://github.com/assinafy/ruby-sdk/issues>
- **API docs:** <https://api.assinafy.com.br/v1/docs>

## Requirements

- Ruby 3.2+ (maintained support: 3.3+; 3.2 is legacy/EOL compatibility)
- Bundler

## Installation

From RubyGems.org:

```ruby
gem 'assinafy'
```

```bash
bundle install
```

From GitHub Packages (mirror):

```ruby
source 'https://rubygems.pkg.github.com/assinafy' do
  gem 'assinafy'
end
```

You'll need a personal access token with `read:packages` scope, configured via:

```bash
bundle config https://rubygems.pkg.github.com/assinafy USERNAME:TOKEN
```

## Quick Start

```ruby
require 'assinafy'

client = Assinafy::Client.new(
  api_key:    ENV.fetch('ASSINAFY_API_KEY'),
  account_id: ENV.fetch('ASSINAFY_ACCOUNT_ID')
)

document = client.documents.upload({ file_path: './contract.pdf' })
signer   = client.signers.create(full_name: 'Alice Silva', email: 'alice@example.com')

assignment = client.assignments.create(
  document['id'],
  method:  'virtual',
  signers: [{ id: signer['id'] }],
  message: 'Please sign the attached contract.'
)

puts assignment['id']
```

## Configuration

```ruby
client = Assinafy::Client.new(
  api_key:        'your-api-key',
  token:          nil,
  account_id:     'your-account-id',
  base_url:       'https://api.assinafy.com.br/v1',
  webhook_secret: nil,
  timeout:        30,
  logger:         Logger.new($stdout)
)
```

- `api_key:` sends `X-Api-Key` (preferred).
- `token:` sends `Authorization: Bearer ...` (legacy session token).
- A client can also be created with no credentials for authentication and public/signer endpoints.
- Account-scoped methods document a per-call account override for multi-workspace tenants.
- Provide a `Logger`-compatible `logger:` to observe upload/assignment/webhook lifecycle messages.

`Client.from_config(hash)` accepts string- or symbol-keyed hashes (e.g. parsed YAML).

## Resources

`Assinafy::Client` exposes twelve accessors — eleven API resources for the current
OpenAPI operations and sandbox-live template routes, plus the local `webhook_verifier` helper:

| Accessor                    | What it covers                                                 |
| --------------------------- | -------------------------------------------------------------- |
| `client.auth`               | Login, social login, password reset, API keys                  |
| `client.accounts`           | Account CRUD, theme, KPI stats, brand logo                     |
| `client.users`              | User profile, notification preferences, cross-account KPIs     |
| `client.documents`          | Upload, list, search, rename, download, delete, verify, tags   |
| `client.signers`            | Workspace signer CRUD + signer self-service endpoints          |
| `client.signer_documents`   | Signer-authenticated multi-document operations + search        |
| `client.assignments`        | List/create/sign/decline/resend/estimate assignments           |
| `client.templates`          | Template creation (file upload), get, list, update, delete     |
| `client.tags`               | Workspace tags                                                 |
| `client.fields`             | Field definitions + validation + type catalog                  |
| `client.webhooks`           | Subscription, event-type catalog, dispatch history, retries    |
| `client.webhook_verifier`   | Optional HMAC-SHA256 verifier for signed deliveries            |

### Authentication

```ruby
client.auth.login(email: 'user@example.com', password: 'secret')
client.auth.social_login(provider: 'google', token: 'id-token', has_accepted_terms: true)
client.auth.link_social_login(provider: 'google', token: 'id-token')
client.auth.create_api_key(password: 'secret')
client.auth.get_api_key
client.auth.delete_api_key
client.auth.change_password(email: 'user@example.com', password: 'old', new_password: 'new')
client.auth.request_password_reset(email: 'user@example.com')
client.auth.reset_password(email: 'user@example.com', new_password: 'new', token: 'reset-token')
```

### Accounts

```ruby
client.accounts.list                                  # accounts the user can access
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
client.users.me # OpenAPI: AuthUser; some sandboxes: { user:, accounts: }; data is passed through
client.users.stats(granularity: 'monthly')            # cross-account KPI rows
client.users.notification_preferences                 # returns all nine owner-email preferences
client.users.update_notification_preferences(SignerDeclined: false) # partial request; returns all nine
```

Both stats methods return rows with `period`, `documents_uploaded`, `documents_sent`,
`signature_requests`, `signature_requests_email`, `signature_requests_whatsapp`,
`signature_requests_viewed`, `signature_requests_completed`, and `documents_certified`.

### Documents

```ruby
client.documents.statuses                                    # GET /documents/statuses
client.documents.list(page: 1, per_page: 20, status: 'pending_signature')
client.documents.search('contract')                          # lightweight GET .../documents/search
client.documents.upload({ file_path: './contract.pdf' }, name: 'Contract v1')
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
client.documents.send_token('document-id') # current OpenAPI also permits no body
client.documents.send_token('document-id', email: 'alice@example.com') # current OpenAPI body
# Current sandbox deployment: recipient: 'alice@example.com', channel: 'email'
client.documents.list_tags('document-id')
client.documents.replace_tags('document-id', ['tag-id-1', 'tag-id-2'])
client.documents.append_tags('document-id', ['tag-id-3'])
# The current sandbox also accepts existing tag names in these arrays.
client.documents.detach_tag('document-id', 'tag-id')

# Template-driven creation
client.documents.create_from_template(
  'template-id',
  [{ role_id: 'role', id: 'signer-id', verification_method: 'Email', notification_methods: ['Email'] }],
  { name: 'Contract', message: 'Please sign', expires_at: '2026-12-31T23:59:00Z' }
)
client.documents.estimate_cost_from_template(
  'template-id',
  [{ role_id: 'role', id: 'signer-id', verification_method: 'Whatsapp' }]
)

# Convenience: signing progress derived from the embedded assignment summary
client.documents.fully_signed?('document-id')
client.documents.signing_progress('document-id')
# => { signed: 1, total: 2, pending: 1, percentage: 50.0 }
```

### Signers (workspace CRUD)

```ruby
client.signers.create(full_name: 'Alice Silva', email: 'alice@example.com')
client.signers.create(full_name: 'Bob Costa',  phone: '+5548999990000') # phone -> whatsapp_phone_number
client.signers.get('signer-id')
client.signers.list(search: 'alice', per_page: 50)  # returns { data:, meta: }
client.signers.update('signer-id', full_name: 'Alice S.', government_id: '00000000000')
client.signers.delete('signer-id')

# Convenience: case-insensitive lookup with built-in 404 handling
client.signers.find_by_email('alice@example.com')
```

### Signers (self-service, signer-access-code)

```ruby
client.signers.self_data(signer_access_code: 'code') # includes has_signature, has_initial, is_signature_reusable
client.signers.accept_terms(signer_access_code: 'code')
client.signers.verify_email(verification_code: '123456', signer_access_code: 'code')
client.signers.confirm_data('document-id', { full_name: 'Alice Silva', email: 'alice@example.com', government_id: '00000000000' }, signer_access_code: 'code')
client.signers.upload_signature(png_bytes, signer_access_code: 'code', type: 'signature', content_type: 'image/png')
# => nil for the documented no-data envelope; some deployments return []
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
  expires_at:     '2026-12-31T23:59:00Z',
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
client.assignments.reset_expiration('document-id', 'assignment-id', '2026-12-31T23:59:00Z')
client.assignments.reset_expiration('document-id', 'assignment-id', nil) # clears the expiry
client.assignments.resend_notification('document-id', 'assignment-id', 'signer-id')
client.assignments.estimate_resend_cost('document-id', 'assignment-id', 'signer-id')
client.assignments.whatsapp_notifications('document-id', 'assignment-id')

# Signer perspective (signer-access-code authentication)
client.assignments.signer_document(signer_access_code: 'code', has_accepted_terms: true)
client.assignments.sign(
  'document-id',
  'assignment-id',
  [{ item_id: 'i1', field_id: 'f1', page_id: 'p1', value: 'Alice' }],
  signer_access_code: 'code'
)
client.assignments.decline('document-id', 'assignment-id', decline_reason: 'Clause 2', signer_access_code: 'code')
```

> The `sign` request body is the API's camelCase body-key exception. This SDK accepts the snake_case keys (`item_id`, `field_id`, `page_id`, `value`) shown above and maps them to `itemId/fieldId/pageId/value` automatically. CamelCase input is also passed through unchanged. Assignment listing separately uses the live-required `accountId` query parameter.

### Signer documents (multi-document workflows)

```ruby
client.signer_documents.current('signer-id', signer_access_code: 'code')
client.signer_documents.list('signer-id', { status: 'pending_signature' }, signer_access_code: 'code')
client.signer_documents.search('signer-id', 'contract', signer_access_code: 'code')
client.signer_documents.sign_multiple(%w[doc-1 doc-2], signer_access_code: 'code')
client.signer_documents.decline_multiple(%w[doc-1 doc-2], decline_reason: 'No', signer_access_code: 'code')
client.signer_documents.download('signer-id', 'document-id', 'pades') # public: no access code needed
```

### Templates

```ruby
client.templates.list(search: 'contract', per_page: 25)
client.templates.get('template-id')
client.templates.create({ file_path: './contract.pdf' })   # multipart file upload
client.templates.create({ buffer: pdf_bytes, file_name: 'contract.pdf' })
client.templates.update('template-id', name: 'Renamed template')
client.templates.delete('template-id')
client.templates.download_page('template-id', 'page-id')   # binary image bytes
```

> Template endpoints (`get`/`create`/`update`/`delete`/`download_page`) are live-verified against the sandbox but are not part of the current OpenAPI document. `create` requires a source file (`multipart/form-data`); the template name defaults to the uploaded file's name.

### Tags

```ruby
client.tags.list(search: 'contract')
client.tags.create(name: 'Contracts', color: 'ff8800')
client.tags.update('tag-id', name: 'Sales Contracts', color: nil)
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

# Authenticated as a workspace user
client.fields.validate('field-id', 'ABC-1234')
# Or authenticated via signer-access-code
client.fields.validate('field-id', 'ABC-1234', signer_access_code: 'code')
client.fields.validate_multiple(
  [{ field_id: 'a', value: '1' }, { field_id: 'b', value: 'value@example.com' }],
  signer_access_code: 'code'
)
```

### Webhooks

```ruby
client.webhooks.list_event_types                              # GET /webhooks/event-types
client.webhooks.get                                           # current subscription (nil on 404)
client.webhooks.register(
  url:    'https://example.com/webhooks/assinafy',
  email:  'ops@example.com',
  events: %w[document_ready document_prepared signer_signed_document]
)
client.webhooks.inactivate                                   # stop deliveries, keep the event set

client.webhooks.list_dispatches(delivered: false, per_page: 50)
client.webhooks.retry_dispatch('dispatch-id')
```

> To stop deliveries, use `inactivate` (the API has no delete-subscription route).

#### Webhook signature verification

The Assinafy API does not currently document a body-signing scheme for outbound webhook deliveries. The SDK ships an opt-in HMAC-SHA256 verifier you can use when a gateway in front of your receiver is configured to sign payloads with a shared secret:

```ruby
verifier = Assinafy::Support::WebhookVerifier.new(ENV.fetch('ASSINAFY_WEBHOOK_SECRET'))
raw_body = request.body.read

# The signature header is one your gateway injects (e.g. Cloudflare / API Gateway).
# Assinafy v1 does not send a signature header itself.
if verifier.verify(raw_body, request.headers['X-Webhook-Signature'])
  event = verifier.extract_event(raw_body)
  verifier.event_type(event)    # => "assignment_created"  (the top-level `event`)
  verifier.event_payload(event) # => event-specific params, or nil
  verifier.event_object(event)  # => the entity acted on, e.g. the document
  verifier.event_subject(event) # => the actor, e.g. the user
end
```

If no `webhook_secret` is configured, `verify` always returns `false` — safe-by-default.

## Responses

Most JSON successes use a `{ "status": ..., "message": ..., "data": ... }` envelope. The SDK
returns the `data` payload (a Hash for single resources, an Array for collection bodies). For
documented no-data envelopes containing only `status`/`message`, it returns `nil`; deployed API
versions that add `data` are passed through. Binary endpoints (`download`, `thumbnail`,
`download_page`, `download_signature`) return raw bytes as an ASCII-8BIT `String`, and
delete-style endpoints return `nil`.

Errors surface the envelope/framework error body through `Assinafy::ApiError`:

```ruby
begin
  client.documents.details('missing-id')
rescue Assinafy::ApiError => e
  e.status_code   # => 404
  e.message       # => "Documento não encontrado."
  e.error_name    # => nil (or "Not Found" for framework errors)
  e.error_code    # => nil (or an integer code)
  e.response_data # => the raw parsed body
end
```

Resource YARD documentation includes request/response examples and calls out known differences
between the current OpenAPI document and the deployed sandbox.

## Pagination

Most `*.list*` methods return `{ data: [...], meta: { ... } }` when the API includes pagination
headers. Ruby-style `per_page:` is transparently converted to the documented `per-page` query
parameter (values above the API's maximum are clamped server-side; the sandbox caps it at 50).
A few endpoints (e.g. `fields.list`) do not paginate and return `meta: nil`.

```ruby
result = client.documents.list(page: 2, per_page: 25)
result[:data] # => Array<Hash>
result[:meta] # => { current_page: 2, per_page: 25, total: 138, last_page: 6 }
```

## High-level workflow helper

`Client#upload_and_request_signatures` bundles upload + signer creation + virtual assignment into a single call:

```ruby
result = client.upload_and_request_signatures(
  source:  { file_path: './contract.pdf' },
  signers: [
    { full_name: 'Alice Silva', email: 'alice@example.com' },
    { full_name: 'Bob Costa',   whatsapp_phone_number: '+5548999990000' }
  ],
  message:    'Please sign.',
  expires_at: '2026-12-31T23:59:00Z'
)

puts result[:document]['id']
puts result[:assignment]['id']
result[:signer_ids] # => ['<sid-1>', '<sid-2>']
```

## Errors

The SDK raises one of:

- `Assinafy::ValidationError` — caller-side input invalid (missing IDs, bad email, etc.).
- `Assinafy::ApiError` — the API returned a non-2xx status. Includes `status_code` and `response_data`.
- `Assinafy::NetworkError` — Faraday connection error or timeout.
- `Assinafy::Error` — base class; other unexpected errors get wrapped here with the operation label.

All inherit a `#context` Hash with debugging metadata.

## Tests

```bash
bundle exec rake spec               # 200+ RSpec examples, including a coverage matrix
bundle exec rubocop                 # Linting
bundle exec bundler-audit check     # Dependency CVEs
```

The coverage spec checks the committed route-to-method matrix for duplicate operations or wrappers, missing public methods, aliases that drift, and unmapped resource methods. It does not download or compare the [OpenAPI document](https://api.assinafy.com.br/v1/docs/openapi.json) during the test run; update the matrix deliberately when the remote contract changes.

### Live integration tests

The suite in [`spec/integration/`](spec/integration/live_sandbox_spec.rb) exercises representative workflows across every resource against the real sandbox. It is not an exhaustive operation-by-operation contract check: OTP- or feature-gated routes may be skipped, and sandbox rollout can lag the current OpenAPI document. The suite is excluded from the default run and only executes when `ASSINAFY_LIVE=1` is set with credentials:

```bash
ASSINAFY_LIVE=1 \
ASSINAFY_API_KEY=... \
ASSINAFY_ACCOUNT_ID=... \
ASSINAFY_TEST_EMAIL=recipient1@example.com \
ASSINAFY_TEST_EMAIL2=recipient2@example.com \
ASSINAFY_BASE_URL=https://sandbox.assinafy.com.br/v1 \
bundle exec rspec spec/integration
```

> These tests create and clean up real resources and, for the assignment flow, send real signature-request emails to the addresses in `ASSINAFY_TEST_EMAIL` / `ASSINAFY_TEST_EMAIL2`.

## Contributing

Pull requests and issues are welcome at <https://github.com/assinafy/ruby-sdk>.

## License

MIT. See [LICENSE](LICENSE).
