# SDK Ruby da Assinafy

*Português · [Read in English](README.en.md)*

[![CI](https://github.com/assinafy/ruby-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/assinafy/ruby-sdk/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/assinafy.svg)](https://rubygems.org/gems/assinafy)

SDK Ruby 3.2+ para todas as operações publicadas da [API Assinafy v1](https://api.assinafy.com.br/v1/docs).
O SDK é para servidores: nunca coloque chave de API, segredo OAuth ou código de signatário em aplicativo móvel,
navegador, log ou repositório. A referência completa, com payloads de cada operação, está em
[docs/API_REFERENCE.md](docs/API_REFERENCE.md); a lista detalhada por recurso está em
[README.en.md](README.en.md).

## Instalação e cliente

```ruby
# Gemfile
gem 'assinafy'
```

```ruby
require 'assinafy'

client = Assinafy::Client.new(
  api_key:    ENV.fetch('ASSINAFY_API_KEY'),
  account_id: ENV.fetch('ASSINAFY_ACCOUNT_ID'),
  base_url:   ENV.fetch('ASSINAFY_BASE_URL', 'https://api.assinafy.com.br/v1'),
  timeout:    30
)
```

Use `https://sandbox.assinafy.com.br/v1` no sandbox. O SDK exige URL absoluta, usa TLS 1.2+ e aceita
credenciais por cliente: prefira `api_key:` para a workspace ou `token:` para sessão/OAuth; se ambas forem
configuradas, a chave não vazia tem precedência. Endpoints públicos e de
signatário removem essas credenciais e enviam apenas o código próprio da operação.

## OAuth 2.1 para marketplace

O fluxo é authorization code com PKCE `S256`. Registre um callback HTTPS e, para cada tentativa, guarde o
`code_verifier`, `state` e emissor esperado no servidor.

```ruby
verifier = Assinafy::OAuth.generate_code_verifier
state    = Assinafy::OAuth.generate_state

url = Assinafy::OAuth.authorization_url(
  client_id:     ENV.fetch('ASSINAFY_CLIENT_ID'),
  redirect_uri:  'https://app.example.com/oauth/callback',
  code_verifier: verifier,
  state:         state,
  scope:         %w[openid profile email documents:read documents:write offline_access]
)
```

No callback, valide `state` e `iss` antes de ler `code` ou `error`; o emissor de produção é
`https://auth.assinafy.com.br`. Troque o código uma única vez, em até 60 segundos:

```ruby
tokens = Assinafy::Client.new.oauth.exchange_code(
  code:          params.fetch(:code),
  client_id:     ENV.fetch('ASSINAFY_CLIENT_ID'),
  code_verifier: verifier,
  redirect_uri:  'https://app.example.com/oauth/callback'
)

oauth_client = Assinafy::Client.new(token: tokens.fetch('access_token'), account_id: 'workspace-id')
```

Persista workspace, escopos, expiração e tokens criptografados. `offline_access` solicita o refresh token, mas não
aparece no `scope` devolvido. Renove sob um lock por conexão e salve atomicamente o novo access token e o novo
refresh token; cada refresh aposenta o anterior. Nunca repita token/revoke por middleware. Ao desconectar, revogue
o refresh token mais recente. `client.oauth.userinfo`, `protected_resource_metadata` e
`authorization_server_metadata` completam o fluxo.

## Fluxo completo de assinatura

1. Faça upload e espere os metadados do PDF.
2. Crie ou reutilize os signatários.
3. Estime o custo.
4. Crie um assignment `virtual` ou `collect`.
5. O signatário aceita os termos, confirma sua identidade e assina ou recusa.
6. Acompanhe atividades/webhooks, baixe o artefato e verifique seu hash.
7. Opcionalmente registre termos contratuais, aditivos, renovação ou encerramento.
8. Exclua somente os recursos que sua aplicação possui, depois dos dependentes.

```ruby
document = client.documents.upload(file_path: '/tmp/contract.pdf')
document = client.documents.wait_until_ready(document.fetch('id'))

signer = client.signers.find_by_email('signer@example.com') ||
         client.signers.create(full_name: 'Example Signer', email: 'signer@example.com')

request = {
  method: 'virtual',
  signers: [{
    signer_id: signer.fetch('id'),
    verification_method: 'Email',
    notification_methods: ['Email']
  }],
  expires_at: (Time.now + 86_400).iso8601
}

cost       = client.assignments.estimate_cost(document.fetch('id'), request)
assignment = client.assignments.create(document.fetch('id'), request)
```

`Client#upload_and_request_signatures` executa upload, signatários e assignment numa chamada e valida todo o
pedido antes da rede. Templates configurados usam `client.documents.create_from_template`; aguarde o estado
`pending_signature` para ler o assignment gerado. `idempotency_key:` evita duplicar a criação após perda de resposta.

Para vários documentos na mesma solicitação, use `client.envelopes.estimate_cost` e `create` com `name`,
`signers` e `documents: [{ id: 'document-id', signer_ids: ['signer-id'] }]`. Cada documento mantém sua assinatura
e artefatos; a criação aceita `idempotency_key:` e `max_total_credits` limita o gasto. A mesma proteção de custo
existe em assignments e templates. Consulte uso e recursos do plano em `accounts.usage` e `accounts.get`.

### Verificação e notificação

| `verification_method` | Notificação | Regras |
| --- | --- | --- |
| `Email` | `Email` | código por e-mail |
| `Whatsapp` | `Whatsapp` | código por WhatsApp |
| `IdDocumentFaceMatchBasic` | `Email` ou `Whatsapp` | documento + selfie; requer CPF válido e recurso na conta |
| `DigitalCertificate` | `Email` ou `Whatsapp` | A1/A3 no Web PKI hospedado; somente assignment `virtual` |

Use exatamente uma notificação por signatário. Etapas são opcionais, mas, quando usadas, devem ser positivas,
contíguas a partir de 1 e atribuídas a todos; valores iguais são paralelos. Um signatário de certificado fica
sozinho na etapa. `expires_at` deve ter fuso e ficar pelo menos uma hora no futuro.

Na biometria, `signers.start_identity_verification(consent: true, signer_access_code:)` devolve uma URL bearer:
preserve o fragmento e não a armazene em logs ou browser storage. O revisor usa `assignments.identity_review`,
`identity_review_image` e `decide_identity_review`. Evidências existem apenas durante `InReview` e não devem ser
cacheadas; imagens e decisões exigem chave/sessão. OAuth pode ler o resumo com `documents:read`. Uma rejeição
cancela o documento. Certificados A1/A3 são concluídos no fluxo hospedado; o SDK não
inventa os endpoints de handshake ainda não publicados.

Operações do signatário usam `signer_access_code:` sem chave/token da workspace. O fluxo inclui termos,
confirmação de dados, OTP, identidade, imagem de assinatura, `assignments.sign`/`decline` e operações em lote em
`signer_documents`.

Assinatura embutida usa `embedded: true` em signatários Email/Whatsapp, origens cadastradas em `accounts` e
`assignments.create_embed_session` no servidor. Exige recurso Embed e chave/sessão, sem OAuth de terceiros.
Downloads de original exigem código do signatário; cópias certificadas usam links temporários autenticados.

## Webhooks e artefatos

Crie o endpoint com `signing_enabled: true`, guarde o segredo `whsec_...` retornado uma vez e verifique o corpo
bruto antes de interpretar JSON:

```ruby
endpoint = client.webhooks.create_endpoint(
  url: 'https://example.com/webhooks/assinafy',
  email: 'ops@example.com',
  events: ['document_certificated'],
  signing_enabled: true
)

verifier = Assinafy::Support::WebhookVerifier.new(endpoint.fetch('secret'))
raise 'invalid webhook' unless verifier.verify_delivery(raw_body, request.headers)

event = verifier.extract_event(raw_body)
```

Deduplicate por `webhook-id`. O timestamp tem tolerância padrão de 300 segundos. Aplicações OAuth precisam guardar
o segredo da criação: a leitura exige chave/sessão; OAuth com `webhooks:write` pode rotacionar e guardar o novo
segredo. `keep_previous: true` mantém ambos por 24 horas. Depois da certificação, use
`documents.download`, `thumbnail`, `download_page`, `activities` e `verify` conforme o artefato.

## Contratos, erros e recursos

Planos com contract tracking usam `client.contracts` para termos, família, aditivo, renovação e encerramento.
Envie o `updated_at` lido como precondição de escrita; conflito concorrente responde `409`. Uma renovação repetível
usa o `term` atual ou `end_date` posterior.

Falhas da API levantam `Assinafy::ApiError`; OAuth usa `OAuthError < ApiError`; entrada inválida usa
`ValidationError`; transporte/TLS usa `NetworkError`. `ApiError#rate_limit` expõe limite/restante/reset e
`#retry_after` o atraso de `429`; o SDK nunca repete automaticamente. Listagens paginadas devolvem
`{ data:, meta: }`, listas simples devolvem `Array`, binários devolvem `String` e respostas vazias devolvem `nil`.

Recursos: `accounts`, `auth`, `oauth`, `users`, `documents`, `contracts`, `signers`, `signer_documents`,
`assignments`, `envelopes`, `templates`, `tags`, `fields`, `webhooks` e `webhook_verifier`. As assinaturas RBS ficam em
[`sig/assinafy.rbs`](sig/assinafy.rbs).

## Desenvolvimento

```bash
bundle exec rspec
bundle exec rubocop --cache false
bundle exec bundler-audit check --update
rbs -I sig validate
ruby scripts/check_api_contract.rb
```

Licença: [MIT](LICENSE).
