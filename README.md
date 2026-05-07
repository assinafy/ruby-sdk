# Assinafy Ruby SDK

Ruby SDK for the [Assinafy API](https://api.assinafy.com.br/v1/docs).

The SDK maps to the documented Assinafy v1 API: authentication, documents, signers, signer document flows, assignments, templates, field definitions, and webhooks.

## Requirements

- Ruby 2.7+
- Bundler

## Installation

```ruby
gem 'assinafy'
```

```bash
bundle install
```

## Quick Start

```ruby
require 'assinafy'

client = Assinafy::Client.new(
  api_key: ENV.fetch('ASSINAFY_API_KEY'),
  account_id: ENV.fetch('ASSINAFY_ACCOUNT_ID')
)

document = client.documents.upload(file_path: './contract.pdf')
signer = client.signers.create(full_name: 'Alice Silva', email: 'alice@example.com')

assignment = client.assignments.create(
  document['id'],
  method: 'virtual',
  signers: [{ id: signer['id'] }],
  message: 'Please sign the attached contract.'
)

puts assignment['id']
```

## Configuration

```ruby
client = Assinafy::Client.new(
  api_key: 'your-api-key',
  token: nil,
  account_id: 'your-account-id',
  base_url: 'https://api.assinafy.com.br/v1',
  webhook_secret: nil,
  timeout: 30
)
```

`api_key` sends `X-Api-Key`. `token` sends `Authorization: Bearer ...`. A client can also be created without credentials for authentication and public signer/document endpoints.

## Resources

```ruby
client.auth.login(email: 'user@example.com', password: 'secret')
client.auth.create_api_key(password: 'secret')

client.documents.statuses
client.documents.list(page: 1, per_page: 20)
client.documents.get('document-id')
client.documents.download('document-id', 'certificated')
client.documents.public_info('document-id')
client.documents.send_token('document-id', recipient: 'alice@example.com', channel: 'email')

client.signers.list(search: 'alice')
client.signers.get('signer-id')
client.signers.update('signer-id', full_name: 'Alice S.')
client.signers.self_data(signer_access_code: 'code')
client.signers.confirm_data('document-id', { email: 'alice@example.com' }, signer_access_code: 'code')

client.assignments.estimate_cost('document-id', signers: [{ verification_method: 'Whatsapp' }])
client.assignments.resend_notification('document-id', 'assignment-id', 'signer-id')
client.assignments.reset_expiration('document-id', 'assignment-id', '2026-06-30T23:59:00Z')
client.assignments.signer_document(signer_access_code: 'code')

client.signer_documents.list('signer-id', { status: 'pending_signature' }, signer_access_code: 'code')
client.signer_documents.sign_multiple(%w[doc-1 doc-2], signer_access_code: 'code')

client.templates.list(status: 'ready')
client.templates.get('template-id')
client.templates.update('template-id', name: 'Updated template')

client.fields.create(type: 'text', name: 'Internal code')
client.fields.validate('field-id', 'ABC-123', signer_access_code: 'code')
client.fields.types

client.webhooks.register(
  url: 'https://example.com/webhooks/assinafy',
  email: 'ops@example.com',
  events: %w[document_ready document_prepared]
)
client.webhooks.list_event_types
```

List methods return `{ data: [...], meta: ... }` when pagination headers are present. Ruby-style `per_page:` is converted to the API's `per-page` query parameter.

## High-Level Workflow

```ruby
result = client.upload_and_request_signatures(
  source: { file_path: './contract.pdf' },
  signers: [
    { full_name: 'Alice Silva', email: 'alice@example.com' },
    { full_name: 'Bob Costa', whatsapp_phone_number: '+5548999990000' }
  ],
  message: 'Please sign.'
)

puts result[:document]['id']
puts result[:assignment]['id']
```

## Webhook Verification

```ruby
verifier = Assinafy::Support::WebhookVerifier.new(ENV.fetch('ASSINAFY_WEBHOOK_SECRET'))
raw_body = request.body.read

if verifier.verify(raw_body, request.headers['X-Assinafy-Signature'])
  event = verifier.extract_event(raw_body)
  puts verifier.event_type(event)
end
```

## Tests

```bash
bundle exec rake spec
```

## License

MIT. See [LICENSE](LICENSE).
