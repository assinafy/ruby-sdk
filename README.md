# Assinafy Ruby SDK

[![CI](https://github.com/assinafy/ruby-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/assinafy/ruby-sdk/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/assinafy.svg)](https://rubygems.org/gems/assinafy)

Ruby SDK for the [Assinafy API v1](https://api.assinafy.com.br/v1/docs).

Maps 1:1 to every documented endpoint in the Assinafy v1 API. Coverage is enforced by [`spec/api_coverage_spec.rb`](spec/api_coverage_spec.rb).

- **Source:** <https://github.com/assinafy/ruby-sdk>
- **Issues:** <https://github.com/assinafy/ruby-sdk/issues>
- **API docs:** <https://api.assinafy.com.br/v1/docs>

## Requirements

- Ruby 3.0+
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

document = client.documents.upload(file_path: './contract.pdf')
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
- All resource methods accept a per-call `account_id_override`, useful for multi-workspace tenants.
- Provide a `Logger`-compatible `logger:` to observe upload/assignment/webhook lifecycle messages.

`Client.from_config(hash)` accepts string- or symbol-keyed hashes (e.g. parsed YAML).

## Resources

The eight resource accessors on `Assinafy::Client` cover every documented endpoint:

| Accessor                    | What it covers                                                 |
| --------------------------- | -------------------------------------------------------------- |
| `client.auth`               | Login, social login, password reset, API keys                  |
| `client.documents`          | Upload, list, get, download, delete, verify, template creation |
| `client.signers`            | Workspace signer CRUD + signer self-service endpoints          |
| `client.signer_documents`   | Signer-authenticated multi-document operations                 |
| `client.assignments`        | Create/sign/decline/resend/estimate assignments                |
| `client.templates`          | Template CRUD                                                  |
| `client.fields`             | Field definitions + validation + type catalog                  |
| `client.webhooks`           | Subscription, event-type catalog, dispatch history, retries    |
| `client.webhook_verifier`   | Optional HMAC-SHA256 verifier for signed deliveries            |

### Authentication

```ruby
client.auth.login(email: 'user@example.com', password: 'secret')
client.auth.social_login(provider: 'google', token: 'id-token', has_accepted_terms: true)
client.auth.create_api_key(password: 'secret')
client.auth.get_api_key
client.auth.delete_api_key
client.auth.change_password(email: 'u@e.com', password: 'old', new_password: 'new')
client.auth.request_password_reset(email: 'u@e.com')
client.auth.reset_password(email: 'u@e.com', new_password: 'new', token: 'reset-token')
```

### Documents

```ruby
client.documents.statuses                                    # GET /documents/statuses
client.documents.list(page: 1, per_page: 20, status: 'pending_signature')
client.documents.upload(file_path: './contract.pdf', name: 'Contract v1')
client.documents.upload(buffer: pdf_bytes, file_name: 'contract.pdf')
client.documents.get('document-id')                          # alias of .details
client.documents.wait_until_ready('document-id', max_wait_seconds: 60)
client.documents.activities('document-id')
client.documents.thumbnail('document-id')                    # binary PNG/JPEG
client.documents.download('document-id', 'certificated')     # binary PDF
client.documents.download_page('document-id', 'page-id')
client.documents.delete('document-id')
client.documents.verify('signature-hash')
client.documents.public_info('document-id')
client.documents.send_token('document-id', recipient: 'alice@example.com', channel: 'email')

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
client.signers.update('signer-id', full_name: 'Alice S.')
client.signers.delete('signer-id')

# Convenience: case-insensitive lookup with built-in 404 handling
client.signers.find_by_email('alice@example.com')
```

### Signers (self-service, signer-access-code)

```ruby
client.signers.self_data(signer_access_code: 'code')
client.signers.accept_terms(signer_access_code: 'code')
client.signers.verify_email(verification_code: '123456', signer_access_code: 'code')
client.signers.confirm_data('document-id', { email: 'alice@example.com', has_accepted_terms: true }, signer_access_code: 'code')
client.signers.upload_signature(png_bytes, signer_access_code: 'code', type: 'signature', content_type: 'image/png')
client.signers.download_signature(signer_access_code: 'code', type: 'signature')
```

### Assignments

```ruby
# Virtual (no positioned fields)
client.assignments.create(
  'document-id',
  method:         'virtual',
  signers:        [{ id: 'signer-1', verification_method: 'Email', notification_methods: ['Email'] }],
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
                                             display_settings: { top: 100, left: 100 } }] }]
)

client.assignments.estimate_cost('document-id', signers: [{ verification_method: 'Whatsapp' }])
client.assignments.reset_expiration('document-id', 'assignment-id', '2026-12-31T23:59:00Z')
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

> The `sign` endpoint is the only place the Assinafy API uses camelCase. This SDK accepts the snake_case keys (`item_id`, `field_id`, `page_id`, `value`) shown above and maps them to the API's `itemId/fieldId/pageId/value` automatically. CamelCase input is also passed through unchanged.

### Signer documents (multi-document workflows)

```ruby
client.signer_documents.current('signer-id', signer_access_code: 'code')
client.signer_documents.list('signer-id', { status: 'pending_signature' }, signer_access_code: 'code')
client.signer_documents.sign_multiple(%w[doc-1 doc-2], signer_access_code: 'code')
client.signer_documents.decline_multiple(%w[doc-1 doc-2], decline_reason: 'No', signer_access_code: 'code')
client.signer_documents.download('signer-id', 'document-id', 'original', signer_access_code: 'code')
```

### Templates

```ruby
client.templates.list(status: 'ready', per_page: 25)
client.templates.get('template-id')
client.templates.create(name: 'My template', message: 'Please sign')
client.templates.update('template-id', name: 'Renamed template')
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
  [{ field_id: 'a', value: '1' }, { field_id: 'b', value: 'x@y.com' }],
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
client.webhooks.inactivate
client.webhooks.delete

client.webhooks.list_dispatches(delivered: false, per_page: 50)
client.webhooks.retry_dispatch('dispatch-id')
```

#### Webhook signature verification

The Assinafy API does not currently document a body-signing scheme for outbound webhook deliveries. The SDK ships an opt-in HMAC-SHA256 verifier you can use when a gateway in front of your receiver is configured to sign payloads with a shared secret:

```ruby
verifier = Assinafy::Support::WebhookVerifier.new(ENV.fetch('ASSINAFY_WEBHOOK_SECRET'))
raw_body = request.body.read

if verifier.verify(raw_body, request.headers['X-Assinafy-Signature'])
  event = verifier.extract_event(raw_body)
  puts verifier.event_type(event), verifier.event_data(event)
end
```

If no `webhook_secret` is configured, `verify` always returns `false` — safe-by-default.

## Pagination

Every `*.list*` method returns `{ data: [...], meta: { ... } }` when the API includes pagination headers. Ruby-style `per_page:` is transparently converted to the documented `per-page` query parameter:

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
bundle exec rake spec     # 100+ RSpec examples, including a coverage matrix
bundle exec rubocop       # Linting
bundle exec bundle-audit  # Dependency CVEs
```

The coverage spec (`spec/api_coverage_spec.rb`) asserts every endpoint documented at <https://api.assinafy.com.br/v1/docs> has a corresponding SDK method.

## Contributing

Pull requests and issues are welcome at <https://github.com/assinafy/ruby-sdk>.

## License

MIT. See [LICENSE](LICENSE).
