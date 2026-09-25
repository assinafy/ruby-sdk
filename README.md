# SDK Ruby da Assinafy

*Português · [Read in English](README.en.md)*

[![CI](https://github.com/assinafy/ruby-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/assinafy/ruby-sdk/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/assinafy.svg)](https://rubygems.org/gems/assinafy)

SDK Ruby para a [API Assinafy v1](https://api.assinafy.com.br/v1/docs) — plataforma brasileira de
assinatura eletrônica de documentos.

O SDK expõe **todas** as operações da API Assinafy v1, incluindo o fluxo OAuth 2.1, e o ciclo de
vida completo de templates suportado. O [`spec/api_coverage_spec.rb`](spec/api_coverage_spec.rb),
versionado no repositório, valida que cada rota mapeia de forma única para um método público do
SDK — se uma operação deixar de ter cobertura, a suíte falha.

Este documento acompanha uma integração do início ao fim. Para consulta rápida por recurso, veja
**[README.en.md](README.en.md)**; para consulta por operação,
[docs/API_REFERENCE.md](docs/API_REFERENCE.md).

---

## Sumário

1. [Requisitos e instalação](#1-requisitos-e-instalação)
2. [Autenticação](#2-autenticação)
3. [Início rápido](#3-início-rápido)
4. [O fluxo completo, passo a passo](#4-o-fluxo-completo-passo-a-passo)
5. [OAuth 2.1](#5-oauth-21)
6. [Métodos de verificação do signatário](#6-métodos-de-verificação-do-signatário)
7. [Templates, campos e tags](#7-templates-campos-e-tags)
8. [Webhooks](#8-webhooks)
9. [Paginação](#9-paginação)
10. [Erros](#10-erros)
11. [Artefatos e verificação pública](#11-artefatos-e-verificação-pública)
12. [Recursos do cliente](#12-recursos-do-cliente)
13. [Ambientes](#13-ambientes)
14. [Assinaturas RBS](#14-assinaturas-rbs)

---

## 1. Requisitos e instalação

- Ruby 3.2+ (suporte mantido: 3.3+; 3.2 é compatibilidade legada/EOL)
- Bundler
- TLS 1.2 ou superior (o SDK recusa TLS 1.0 e 1.1)

Do RubyGems.org:

```ruby
# Gemfile
gem 'assinafy'
```

```bash
bundle install
```

Do GitHub Packages (mirror):

```ruby
source 'https://rubygems.pkg.github.com/assinafy' do
  gem 'assinafy'
end
```

Você vai precisar de um personal access token com escopo `read:packages`:

```bash
bundle config https://rubygems.pkg.github.com/assinafy USUARIO:TOKEN
```

---

## 2. Autenticação

A Assinafy aceita três credenciais. Escolha pela pergunta "**quem** está agindo?".

| Credencial | Quem age | Quando usar |
| --- | --- | --- |
| **Chave de API** (`api_key:`) | a própria workspace | integrações de back-end. Permanente. Enviada como `X-Api-Key`. |
| **Token de sessão** (`token:`) | o usuário que fez login | depois de `client.auth.login`. JWT, expira em ~1 hora. |
| **OAuth 2.1** (`token:`) | um aplicativo, **em nome de** um usuário | apps de marketplace, integrações de terceiros, assistentes de IA. Veja a [seção 5](#5-oauth-21). |

```ruby
require 'assinafy'

client = Assinafy::Client.new(
  api_key:        ENV.fetch('ASSINAFY_API_KEY'),
  account_id:     ENV.fetch('ASSINAFY_ACCOUNT_ID'),
  base_url:       'https://api.assinafy.com.br/v1', # padrão
  webhook_secret: ENV['ASSINAFY_WEBHOOK_SECRET'],
  timeout:        30,
  logger:         Logger.new($stdout)
)
```

- Configure **exatamente uma** credencial. Se `api_key:` e `token:` forem informados, o SDK envia
  apenas `X-Api-Key`.
- Um cliente também pode ser criado **sem credenciais**, para login, OAuth, e endpoints
  públicos/de signatário.
- `base_url:` precisa ser uma URL `http`/`https` absoluta. Qualquer outra coisa — um host sem
  esquema, um caminho relativo, outro esquema — levanta `Assinafy::ValidationError` em vez de
  anexar suas credenciais a ela. Barra ao final é removida.
- Métodos com escopo de conta aceitam uma sobrescrita por chamada, para tenants com múltiplos
  workspaces.
- As requisições enviam `User-Agent: Assinafy-Ruby-SDK/v<Assinafy::VERSION>`.

`Client.from_config(hash)` aceita hashes com chaves string ou símbolo (por exemplo, YAML já
interpretado).

### Gerenciando a chave de API

```ruby
client.auth.create_api_key(password: 'senha-atual')  # => { 'api_key' => '...' } — exibida uma única vez
client.auth.get_api_key                              # => { 'api_key' => '****...9Jdr' } — mascarada
client.auth.delete_api_key                           # => nil
```

Gerar uma chave nova **invalida a anterior**. Nunca exponha a chave em um front-end.

---

## 3. Início rápido

O caminho mais curto do PDF até o pedido de assinatura:

```ruby
resultado = client.upload_and_request_signatures(
  source:  './contrato.pdf',
  signers: [{ full_name: 'Ana Silva', email: 'ana@exemplo.com.br' }],
  message: 'Por favor, assine o contrato em anexo.'
)

resultado[:document]['id']    # => "1032009d72b364f377ff270405cc"
resultado[:assignment]['id']  # => "19e99aa0633e32ac13f845c08db"
resultado[:signer_ids]        # => ["19e6b92e7895332ed9708535d8c"]
```

Esse helper faz upload, espera o processamento, cria os signatários e abre um assignment
`virtual`. Ele valida o payload inteiro **antes** de enviar qualquer coisa, então um
`expires_at` malformado não deixa um documento órfão para trás.

> **Não é transacional.** Se uma chamada posterior falhar, o documento enviado e os signatários
> já criados continuam existindo. Em caso de erro, `e.context[:document]` e
> `e.context[:signer_ids]` trazem o que foi criado, para você limpar.

A seção seguinte abre esse helper passo a passo — use-a quando precisar de controle sobre
qualquer etapa.

---

## 4. O fluxo completo, passo a passo

### 4.1 Enviar o documento

```ruby
documento = client.documents.upload('./contrato.pdf', name: 'contrato-acme.pdf')
documento['id']     # => "1032009d72b364f377ff270405cc"
documento['status'] # => "uploaded"
```

Aceita um caminho, ou um Hash com `:file_path`, ou `:buffer` + `:file_name` para bytes em
memória:

```ruby
client.documents.upload(buffer: pdf_bytes, file_name: 'contrato.pdf')
```

Somente PDF, no máximo 25 MB. O SDK confere a extensão, o tamanho e o cabeçalho `%PDF-` antes de
enviar.

### 4.2 Esperar o processamento

A Assinafy extrai páginas e metadados de forma assíncrona. Só é possível abrir um assignment
depois disso:

```ruby
documento = client.documents.wait_until_ready(
  documento['id'],
  max_wait_seconds:      30,
  poll_interval_seconds: 2
)
documento['status'] # => "metadata_ready"
documento['pages']  # => [{ 'id' => '...', 'number' => 1, 'height' => 1651, 'width' => 1275 }]
```

Erros de rede durante a espera são tolerados e reprocessados; um status terminal
(`failed`, `expired`, `rejected_by_*`) interrompe imediatamente com `Assinafy::Error`.

### 4.3 Criar os signatários

```ruby
signatario = client.signers.create(
  full_name:             'Ana Silva',
  email:                 'ana@exemplo.com.br',
  whatsapp_phone_number: '+5511999999999',  # obrigatório para verificação por WhatsApp
  government_id:         '00000000000'      # obrigatório para certificado digital
)
signatario['id'] # => "19e6b92e7895332ed9708535d8c"
```

Signatários pertencem à conta e podem ser reaproveitados entre documentos:

```ruby
existente = client.signers.find_by_email('ana@exemplo.com.br')  # paginação percorrida pelo SDK
signatario = existente || client.signers.create(full_name: 'Ana Silva', email: 'ana@exemplo.com.br')
```

### 4.4 Estimar o custo (opcional, recomendado)

Antes de enviar — principalmente com WhatsApp ou certificado digital, que são cobrados:

```ruby
client.assignments.estimate_cost(
  documento['id'],
  signers: [{ verification_method: 'DigitalCertificate' }]
)
```

Aqui os signatários podem ser descritos só pelo método, sem `id`.

### 4.5 Abrir o assignment

Um assignment é o convite para assinar um documento. Dois métodos:

**`virtual`** — sem campos posicionados; o signatário aceita o documento inteiro.

```ruby
assignment = client.assignments.create(
  documento['id'],
  method:  'virtual',
  signers: [
    { id: signatario['id'], verification_method: 'Email', notification_methods: ['Email'], step: 1 }
  ],
  message:        'Por favor, assine o contrato em anexo.',
  expires_at:     '2026-12-31T23:59:00Z',
  copy_receivers: []                       # IDs que só recebem cópia
)

assignment['signing_urls']
# => [{ 'signer_id' => '19e6b...', 'url' => 'https://.../sign/...' }]
```

`step` define a ordem: todos do passo 1 assinam antes do passo 2. Omita para assinatura
simultânea.

**`collect`** — campos posicionados página a página.

```ruby
client.assignments.create(
  documento['id'],
  method:  'collect',
  signers: [{ id: signatario['id'] }],
  entries: [{
    page_id: documento['pages'].first['id'],
    fields:  [{
      signer_id:        signatario['id'],
      field_id:         campo['id'],
      display_settings: { left: 100, top: 100, width: 240, height: 48, fontSize: 16 }
    }]
  }]
)
```

O SDK aceita `signers: ['id1', 'id2']` (IDs puros), `signers: [{ id: ... }]` (descritores
completos) e o formato legado `signer_ids:`. Tudo é normalizado para o corpo que a API espera.

### 4.6 O signatário assina

Essas chamadas usam o **código de acesso do signatário**, não suas credenciais de workspace — o
SDK remove `X-Api-Key`/`Authorization` delas automaticamente. Um cliente sem credenciais basta:

```ruby
signatario_client = Assinafy::Client.new
codigo = 'codigo-de-acesso-do-link-de-assinatura'

# 1. Carregar o documento a assinar
doc = signatario_client.assignments.signer_document(
  signer_access_code: codigo,
  has_accepted_terms: true
)

# 2. Aceitar os termos e confirmar a identidade
signatario_client.signers.accept_terms(signer_access_code: codigo)
signatario_client.signers.confirm_data(
  doc['id'], { full_name: 'Ana Silva', government_id: '00000000000' },
  signer_access_code: codigo
)

# 3. Verificar o código de uso único (OTP) recebido por e-mail ou WhatsApp
signatario_client.signers.verify_email(verification_code: '123456', signer_access_code: codigo)

# 4. Enviar a imagem da assinatura
signatario_client.signers.upload_signature(
  File.binread('assinatura.png'), signer_access_code: codigo, type: 'signature'
)
```

Para um assignment **virtual**:

```ruby
signatario_client.signer_documents.sign_multiple([doc['id']], signer_access_code: codigo)
```

Para um assignment **collect**, envie cada item posicionado:

```ruby
itens = doc.fetch('assignment').fetch('items').map do |item|
  {
    item_id:  item.fetch('id'),
    field_id: item.dig('field', 'id'),
    page_id:  item.dig('page', 'id'),
    value:    'Aceito'
  }
end

signatario_client.assignments.sign(
  doc['id'], doc.dig('assignment', 'id'), itens, signer_access_code: codigo
)
```

Para recusar:

```ruby
signatario_client.assignments.decline(
  doc['id'], doc.dig('assignment', 'id'),
  decline_reason: 'Valores divergentes da proposta',
  signer_access_code: codigo
)
```

### 4.7 Acompanhar o andamento

```ruby
client.documents.signing_progress(documento['id'])
# => { signed: 1, total: 3, pending: 2, percentage: 33.33 }

client.documents.fully_signed?(documento['id'])  # => false
client.documents.activities(documento['id'])     # trilha completa de eventos
```

Reenviar a notificação de um signatário (também é cobrado — estime antes):

```ruby
client.assignments.estimate_resend_cost(documento['id'], assignment['id'], signatario['id'])
client.assignments.resend_notification(documento['id'], assignment['id'], signatario['id'])
```

Estender o prazo:

```ruby
client.assignments.reset_expiration(documento['id'], assignment['id'], '2027-01-31T23:59:00Z')
```

Para acompanhar sem polling, use [webhooks](#8-webhooks).

### 4.8 Baixar e verificar

```ruby
File.binwrite('assinado.pdf',   client.documents.download(documento['id'], 'certificated'))
File.binwrite('original.pdf',   client.documents.download(documento['id'], 'original'))
File.binwrite('pacote.zip',     client.documents.download(documento['id'], 'bundle'))

client.documents.verify('hash-da-assinatura')  # verificação pública, sem autenticação
```

### 4.9 Organizar e limpar

```ruby
client.documents.rename(documento['id'], 'Contrato Acme — assinado')
client.documents.append_tags(documento['id'], [tag['id']])

client.documents.delete(documento['id'])
client.signers.delete(signatario['id'])
```

Apague só depois de concluir o que depende do recurso. Alguns respondem `409` enquanto ainda
estão em processamento ou referenciados.

---

## 5. OAuth 2.1

Use OAuth quando um aplicativo age **em nome de um usuário**, com a permissão dele — apps de
marketplace, integrações de terceiros, assistentes de IA. Diferente da chave de API, o token
vale para **uma** workspace e carrega apenas os escopos que o usuário aprovou.

Fluxo *authorization code* com **PKCE obrigatório** (o servidor aceita apenas `S256`).

### Escopos

| Escopo | Concede |
| --- | --- |
| `documents:read` | ler documentos, páginas, tags, signatários, assignments e atividades |
| `documents:write` | criar, alterar e excluir documentos e gerenciar seus signatários e assignments |
| `templates:read` | ler templates, páginas, papéis, campos e tags |
| `templates:write` | criar, alterar e excluir templates |
| `account:read` | ler perfil, tema e logo da workspace |
| `webhooks:write` | configurar e desativar a assinatura de webhooks da workspace |
| `openid` | identificar o usuário (claim `sub`) e habilitar `/oauth/userinfo` |
| `profile` | incluir o nome do usuário nas claims |
| `email` | incluir o e-mail e seu status de verificação nas claims |
| `offline_access` | receber um *refresh token* |

Um token OAuth **nunca** alcança faturamento, ciclo de vida da conta, gerenciamento de
credenciais ou superfícies administrativas — independentemente do escopo.

### Passo 1 — redirecionar o usuário

```ruby
verificador = Assinafy::OAuth.generate_code_verifier
state       = Assinafy::OAuth.generate_state

session[:assinafy_code_verifier] = verificador   # guarde os dois na sessão
session[:assinafy_state]         = state

redirect_to Assinafy::OAuth.authorization_url(
  client_id:     ENV.fetch('ASSINAFY_CLIENT_ID'),
  redirect_uri:  'https://app.exemplo.com.br/oauth/callback',
  code_verifier: verificador,
  scope:         %w[documents:read documents:write offline_access],
  state:         state
)
```

O `code_challenge` é derivado do verificador (`S256`) — o verificador em si nunca vai para a URL.

### Passo 2 — trocar o código por tokens

```ruby
raise 'state divergente' unless params[:state] == session.delete(:assinafy_state)

tokens = Assinafy::Client.new.oauth.exchange_code(
  code:          params.fetch(:code),
  client_id:     ENV.fetch('ASSINAFY_CLIENT_ID'),
  code_verifier: session.delete(:assinafy_code_verifier),
  redirect_uri:  'https://app.exemplo.com.br/oauth/callback'
)

tokens['access_token']   # => "..."
tokens['expires_in']     # => 3600
tokens['refresh_token']  # => presente apenas com offline_access
tokens['scope']          # => "documents:read documents:write"
```

Compare o `state` **antes** de trocar o código — é a proteção contra CSRF.

### Passo 3 — agir como o usuário

```ruby
usuario = Assinafy::Client.new(
  token:      tokens.fetch('access_token'),
  account_id: ENV.fetch('ASSINAFY_ACCOUNT_ID')
)

usuario.documents.list
usuario.oauth.userinfo  # => { 'sub' => ..., 'name' => ..., 'email' => ... }
```

### Renovar e revogar

```ruby
novos = client.oauth.refresh(
  refresh_token: refresh_token_guardado,
  client_id:     ENV.fetch('ASSINAFY_CLIENT_ID')
)

client.oauth.revoke(
  token:           refresh_token_guardado,
  client_id:       ENV.fetch('ASSINAFY_CLIENT_ID'),
  token_type_hint: 'refresh_token'
)
```

Sem `offline_access` não há refresh token: quando o access token expirar, mande o usuário pelo
fluxo de autorização de novo. Revogar um refresh token invalida também os access tokens emitidos
a partir dele.

> O SDK **não renova o token automaticamente**. Guarde `expires_in`, renove antes de expirar, e
> trate `invalid_grant` reiniciando o fluxo de autorização.

### Descoberta

Em vez de fixar endpoints no código:

```ruby
recurso = client.oauth.protected_resource_metadata
recurso['authorization_servers']  # => ["https://auth.assinafy.com.br"]

servidor = client.oauth.authorization_server_metadata
servidor['token_endpoint']                    # => "https://api.assinafy.com.br/v1/oauth/token"
servidor['code_challenge_methods_supported']  # => ["S256"]
```

### Erros OAuth

Os endpoints OAuth respondem com o objeto plano da RFC 6749, não com o envelope da API. O SDK
levanta `Assinafy::OAuthError` (subclasse de `Assinafy::ApiError`):

```ruby
begin
  client.oauth.exchange_code(...)
rescue Assinafy::OAuthError => e
  e.error             # => "invalid_grant"
  e.error_description # => "The authorization code is invalid or has expired."
  e.status_code       # => 400
end
```

Num `403`, `e.context[:www_authenticate]` traz o desafio que **nomeia o escopo faltante**.

---

## 6. Métodos de verificação do signatário

Definidos por signatário ao criar o assignment. Verificação e notificação são **acopladas**:
envie um, os dois, ou nenhum — o lado que faltar é inferido. Sem nenhum dos dois, ambos assumem
`Email`.

| Método | Como funciona | Custo por signatário |
| --- | --- | --- |
| `Email` *(padrão)* | Código de uso único (OTP) por e-mail, exigido antes de assinar | Gratuito |
| `Whatsapp` | Código de uso único (OTP) por WhatsApp | Verificação gratuita; notificação 0,45 crédito, só em planos pagos |
| `DigitalCertificate` | O signatário assina com o **próprio certificado ICP-Brasil (A1/A3)**, pela extensão de navegador Web PKI, gerando uma assinatura **PAdES qualificada** | 2 créditos |

Os valores aceitos estão publicados em
`Assinafy::Resources::AssignmentResource::VERIFICATION_METHODS` e `::NOTIFICATION_METHODS`. O SDK
valida localmente: um valor fora do enum levanta `ValidationError` **antes** de a requisição
sair — e portanto antes de qualquer signatário ser criado para aquele assignment.

Combinações permitidas: `Email` → notifica por `Email`; `Whatsapp` → notifica por `Whatsapp`;
`DigitalCertificate` → notifica por `Email` **ou** `Whatsapp`.

### Certificado digital ICP-Brasil (A1/A3)

Exige o recurso **Certificado Digital** na conta (planos Standard e Pro), CPF ou CNPJ em
`government_id` do signatário, e exatamente **um signatário por certificado naquele passo**. Um
CPF exige o certificado daquela pessoa (e-CPF, ou e-CNPJ que a nomeie como representante legal);
um CNPJ exige um e-CNPJ da empresa, de qualquer um de seus representantes.

```ruby
client.assignments.create(
  documento['id'],
  method:  'virtual',
  signers: [{ id: signatario['id'], verification_method: 'DigitalCertificate', step: 1 }]
)
```

Antes de abrir o assignment, o signatário precisa confirmar os dados de identidade e aceitar os
termos. O endpoint comum de assinatura **rejeita** signatários por certificado — a assinatura
deles é produzida por um handshake de dois passos com a extensão Web PKI:

```
POST /v1/signers/certificate/start     → data.token   (token da operação Web PKI)
        ↓  o navegador assina o token com o certificado do signatário
POST /v1/signers/certificate/complete  → data.signerName
```

> Essas duas rotas são extensões que **não constam do documento OpenAPI publicado**: a
> autenticação e os esquemas de requisição/resposta delas não são documentados. Como envolveria
> adivinhar o payload, o SDK **não** expõe essas duas chamadas — fale com a Assinafy antes de
> habilitar o fluxo em produção.

Concluído o fluxo, baixar o artefato `pades` devolve a assinatura PAdES qualificada.

---

## 7. Templates, campos e tags

### Templates

Um template é um PDF reutilizável com papéis e campos definidos:

```ruby
template = client.templates.create('./contrato-modelo.pdf', name: 'Contrato padrão')
client.templates.list
client.templates.get(template['id'])
client.templates.update(template['id'], name: 'Contrato padrão v2')
client.templates.download_page(template['id'], pagina_id)
client.templates.delete(template['id'])
```

Gerar um documento a partir de um template:

```ruby
client.documents.estimate_cost_from_template(
  template['id'], [{ full_name: 'Ana Silva', email: 'ana@exemplo.com.br' }]
)

documento = client.documents.create_from_template(
  template['id'], [{ full_name: 'Ana Silva', email: 'ana@exemplo.com.br' }]
)
```

### Campos

Definições de campo reutilizáveis, com validação opcional por regex:

```ruby
campo = client.fields.create(name: 'CPF', type: 'text', regex: '\A\d{11}\z')
client.fields.types      # tipos de campo disponíveis
client.fields.list
client.fields.validate(campo['id'], '12345678901')
client.fields.validate_multiple([{ field_id: campo['id'], value: '12345678901' }])
client.fields.delete(campo['id'])
```

### Tags

```ruby
tag = client.tags.create(name: 'Contratos 2026', color: '2072b9')
client.tags.list
client.tags.update(tag['id'], name: 'Contratos')
client.tags.delete(tag['id'], force: true)

client.documents.list_tags(documento['id'])
client.documents.append_tags(documento['id'], [tag['id']])
client.documents.replace_tags(documento['id'], [tag['id']])
client.documents.detach_tag(documento['id'], tag['id'])
```

---

## 8. Webhooks

Registrar a assinatura de eventos da conta:

```ruby
client.webhooks.list_event_types  # eventos disponíveis

client.webhooks.register(
  url:       'https://app.exemplo.com.br/webhooks/assinafy',
  email:     'ops@exemplo.com.br',   # para avisos de falha de entrega
  events:    %w[document.completed signer.declined],
  is_active: true
)

client.webhooks.get            # nil quando não há assinatura
client.webhooks.inactivate
client.webhooks.list_dispatches
client.webhooks.retry_dispatch(dispatch_id)
```

Verificar a assinatura HMAC-SHA256 do payload recebido:

```ruby
verificador = client.webhook_verifier   # usa o webhook_secret do cliente

post '/webhooks/assinafy' do
  corpo      = request.body.read
  assinatura = request.env['HTTP_X_ASSINAFY_SIGNATURE']

  halt 401 unless verificador.verify(corpo, assinatura)

  evento = verificador.extract_event(corpo)
  case verificador.event_type(evento)
  when 'document.completed' then processar(verificador.event_data(evento))
  end

  200
end
```

`verify` usa comparação de tempo constante e devolve `false` — nunca levanta — para segredo
ausente, assinatura ausente ou corpo inválido.

---

## 9. Paginação

Os métodos `*.list*` devolvem `{ data: [...], meta: { ... } }` quando a API envia cabeçalhos de
paginação:

```ruby
pagina = client.documents.list(page: 1, per_page: 50)
pagina[:data]  # => [Documento, ...]
pagina[:meta]  # => { current_page: 1, per_page: 50, total: 128, last_page: 3 }
```

O `per_page:` em estilo Ruby é convertido para o parâmetro `per-page` documentado. Valores acima
do máximo são limitados pelo servidor (o sandbox limita em 50). Alguns endpoints não paginam e
devolvem `meta: nil`.

```ruby
def cada_documento(client)
  return to_enum(:cada_documento, client) unless block_given?

  pagina = 1
  loop do
    resultado = client.documents.list(page: pagina, per_page: 50)
    resultado[:data].each { |documento| yield documento }

    meta = resultado[:meta]
    break unless meta && meta[:last_page] && pagina < meta[:last_page]

    pagina += 1
  end
end
```

---

## 10. Erros

```ruby
begin
  client.documents.details(documento_id)
rescue Assinafy::ValidationError => e
  # entrada inválida — detectada ANTES de qualquer requisição
  warn e.errors.inspect
rescue Assinafy::OAuthError => e
  # falha em endpoint OAuth (subclasse de ApiError)
  warn "#{e.error}: #{e.error_description}"
rescue Assinafy::ApiError => e
  # a API respondeu com erro
  warn "Assinafy respondeu #{e.status_code}: #{e.message}"
  warn e.response_data.inspect
rescue Assinafy::NetworkError => e
  # conexão, timeout ou TLS
  warn "Falha de rede: #{e.message}"
rescue Assinafy::Error => e
  # qualquer outra falha do SDK
  warn e.context.inspect
end
```

Toda exceção do SDK deriva de `Assinafy::Error` e carrega um `#context` com detalhes úteis para
depuração. `ApiError` trata as duas formas de corpo de erro da API — o erro de framework
(`{"name":..., "code":..., "status":...}`) e o envelope de aplicação
(`{"status":..., "data":null, "message":...}`) — inclusive quando um `200` traz um `status`
interno de falha.

---

## 11. Artefatos e verificação pública

As atividades de um documento devolvem todos os eventos registrados, cada um com um snapshot do
`payload` do evento e a `origin` da requisição (`ip`, `user-agent`).

| Artefato | Conteúdo |
| --- | --- |
| `original` | O PDF enviado, como recebido |
| `certificated` | O documento assinado, com a certificação da plataforma |
| `certificate-page` | Apenas a página de certificação |
| `pades` | Assinaturas ICP-Brasil dos signatários + caixa de certificação — só existe em documentos que tiveram signatários por certificado digital |
| `bundle` | Zip com `original`, `certificated` e `certificate-page`, mais o `pades` quando houver |

A verificação pública confere um documento assinado pelo hash da assinatura, sem autenticação:

```ruby
Assinafy::Client.new.documents.verify('hash-da-assinatura')
```

Ela devolve o resultado da Assinafy; não valida independentemente a assinatura do PDF nem a
cadeia de certificação.

---

## 12. Recursos do cliente

| Acessor | Cobre |
| --- | --- |
| `client.auth` | login, login social, senha, chaves de API |
| `client.oauth` | OAuth 2.1: token, refresh, revoke, userinfo, descoberta |
| `client.accounts` | workspaces, tema, KPIs, logo |
| `client.users` | perfil próprio, KPIs, preferências de notificação |
| `client.documents` | upload, listagem, download, ciclo de vida, tags, verificação |
| `client.signers` | CRUD de signatários e todo o autoatendimento do signatário |
| `client.signer_documents` | documentos do signatário, assinar/recusar em lote |
| `client.assignments` | pedidos de assinatura, custos, reenvios, assinatura, recusa |
| `client.templates` | ciclo de vida de templates |
| `client.tags` | CRUD de tags |
| `client.fields` | definições de campo e validação |
| `client.webhooks` | assinatura, entregas, reenvio |
| `client.webhook_verifier` | verificação HMAC do payload recebido |

`client.faraday_connection` expõe a conexão Faraday para middleware ou inspeção em testes.

---

## 13. Ambientes

| | |
| --- | --- |
| Produção | `https://api.assinafy.com.br/v1` |
| Sandbox | `https://sandbox.assinafy.com.br/v1` |

O sandbox é gratuito e espelha a produção 1 para 1 — mesmas rotas, mesmos contratos, incluindo
OAuth 2.1 e certificado digital. Troque apenas a `base_url` para testar a integração de ponta a
ponta antes de ir para produção.

---

## 14. Assinaturas RBS

`sig/assinafy.rbs` acompanha a gem, então consumidores que usam RBS têm as assinaturas
publicadas. Desde a remoção do Steep elas não são verificadas por um type checker a cada build;
em vez disso, [`spec/rbs_signature_spec.rb`](spec/rbs_signature_spec.rb) garante que todo método
público de recurso, do `Client` e de `Assinafy::OAuth` tenha uma assinatura declarada — nenhum
método novo chega à gem sem uma.

---

## Documentação

- **[README.en.md](README.en.md)** — referência completa por recurso, em inglês
- [docs/API_REFERENCE.md](docs/API_REFERENCE.md) — referência por operação
- [CHANGELOG.md](CHANGELOG.md) — histórico de versões
- [Documentação da API](https://api.assinafy.com.br/v1/docs)

## Licença

Distribuído sob a licença [MIT](LICENSE).
