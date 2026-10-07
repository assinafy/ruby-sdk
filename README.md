# SDK Ruby da Assinafy

*Português · [Read in English](README.en.md)*

[![CI](https://github.com/assinafy/ruby-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/assinafy/ruby-sdk/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/assinafy.svg)](https://rubygems.org/gems/assinafy)

SDK Ruby para a [API Assinafy v1](https://api.assinafy.com.br/v1/docs) — plataforma brasileira de
assinatura eletrônica de documentos.

O SDK expõe **todas** as operações da API Assinafy v1, incluindo OAuth 2.1, autenticação em dois
fatores, endpoints de webhook com assinatura nativa, e o ciclo de vida completo de templates. O
[`spec/api_coverage_spec.rb`](spec/api_coverage_spec.rb), versionado no repositório, valida que cada
rota mapeia de forma única para um método público do SDK — se uma operação deixar de ter cobertura,
a suíte falha.

Este documento acompanha uma integração do início ao fim, na ordem em que ela acontece. Para
consulta rápida por recurso, veja **[README.en.md](README.en.md)**; para consulta por operação,
[docs/API_REFERENCE.md](docs/API_REFERENCE.md).

---

## Sumário

1. [Instalação, configuração e ambientes](#1-instalação-configuração-e-ambientes)
2. [Autenticação](#2-autenticação)
3. [Conexão OAuth 2.1 (apps de marketplace)](#3-conexão-oauth-21-apps-de-marketplace)
4. [Enviar o documento e esperar os metadados](#4-enviar-o-documento-e-esperar-os-metadados)
5. [Signatários](#5-signatários)
6. [Métodos de verificação e notificação](#6-métodos-de-verificação-e-notificação)
7. [Estimar o custo](#7-estimar-o-custo)
8. [Abrir o assignment](#8-abrir-o-assignment)
9. [A experiência do signatário](#9-a-experiência-do-signatário)
10. [Webhooks: endpoints e verificação de assinatura](#10-webhooks-endpoints-e-verificação-de-assinatura)
11. [Andamento, download e verificação](#11-andamento-download-e-verificação)
12. [Organizar e limpar](#12-organizar-e-limpar)
13. [Erros](#13-erros)
14. [Paginação](#14-paginação)
15. [Recursos do cliente](#15-recursos-do-cliente)
16. [Assinaturas RBS](#16-assinaturas-rbs)

---

## 1. Instalação, configuração e ambientes

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

Do GitHub Packages (mirror), com um personal access token de escopo `read:packages`:

```ruby
source 'https://rubygems.pkg.github.com/assinafy' do
  gem 'assinafy'
end
```

```bash
bundle config https://rubygems.pkg.github.com/assinafy USUARIO:TOKEN
```

### Ambientes

| Ambiente | `base_url` | Servidor de autorização OAuth |
| --- | --- | --- |
| Produção | `https://api.assinafy.com.br/v1` (padrão) | `https://auth.assinafy.com.br` |
| Sandbox | `https://sandbox.assinafy.com.br/v1` | `https://auth-sandbox.assinafy.com.br` |

O sandbox é gratuito: use-o para testar a integração antes de ir para produção, trocando a
`base_url` e, no OAuth, o servidor de autorização. Nunca envie uma chave de API do sandbox para a
produção, nem o contrário. Os endpoints de webhook e a autenticação em dois fatores estão
disponíveis em produção (`api.assinafy.com.br`).

### Configuração

```ruby
require 'assinafy'
require 'logger'

client = Assinafy::Client.new(
  api_key:        ENV.fetch('ASSINAFY_API_KEY'),
  account_id:     ENV.fetch('ASSINAFY_ACCOUNT_ID'),
  base_url:       ENV.fetch('ASSINAFY_BASE_URL', 'https://api.assinafy.com.br/v1'),
  webhook_secret: ENV['ASSINAFY_WEBHOOK_SECRET'],   # whsec_... do endpoint de webhook
  timeout:        30,
  logger:         Logger.new($stdout)
)
```

- `base_url:` precisa ser uma URL `http`/`https` absoluta. Qualquer outra coisa — um host sem
  esquema, um caminho relativo, outro esquema — levanta `Assinafy::ValidationError` em vez de
  anexar suas credenciais a ela. A barra final é removida. `Configuration#base_url=` e
  `#timeout=` validam da mesma forma que o construtor.
- Métodos com escopo de conta aceitam uma sobrescrita de `account_id` por chamada, para tenants com
  múltiplas workspaces.
- O `logger:` recebe mensagens de ciclo de vida do SDK, nunca corpos de requisição ou credenciais.
- Toda requisição envia `User-Agent: Assinafy-Ruby-SDK/v<Assinafy::VERSION>`.
- `Client.from_config(hash)` aceita hashes com chaves string ou símbolo (por exemplo, YAML já
  interpretado).

---

## 2. Autenticação

A Assinafy aceita três credenciais. Escolha pela pergunta "**quem** está agindo?".

| Credencial | Quem age | Quando usar |
| --- | --- | --- |
| **Chave de API** (`api_key:`) | a própria workspace | integrações de back-end. Permanente. Enviada como `X-Api-Key`. |
| **Token de sessão** (`token:`) | o usuário que fez login | depois de `client.auth.login`. JWT, expira em ~1 hora. |
| **OAuth 2.1** (`token:`) | um aplicativo, **em nome de** um usuário | apps de marketplace, integrações de terceiros, assistentes de IA. Veja a [seção 3](#3-conexão-oauth-21-apps-de-marketplace). |

Configure **exatamente uma** credencial por cliente; se `api_key:` e `token:` forem informados, o
SDK envia apenas `X-Api-Key`. Um cliente **sem credenciais** serve para login, OAuth e endpoints
públicos ou de signatário — o SDK remove `X-Api-Key`/`Authorization` dessas chamadas de qualquer
forma.

### Login com e-mail e senha

```ruby
publico = Assinafy::Client.new
sessao  = publico.auth.login(email: 'usuario@example.com', password: ENV.fetch('ASSINAFY_PASSWORD'))
```

Quando o usuário tem **autenticação em dois fatores** ativa, o login não devolve `access_token`:
devolve um desafio com `mfa_token`. Troque-o pelo código do aplicativo autenticador, ou por um
código de recuperação:

```ruby
if sessao['mfa_token']
  sessao = publico.auth.verify_mfa(
    mfa_token: sessao['mfa_token'],
    code:      '123456'            # ou um código de recuperação, como "ABCD-EFGH-JKMN"
  )
end

usuario = Assinafy::Client.new(
  token:      sessao.fetch('access_token'),
  account_id: sessao.fetch('accounts').first.fetch('id')
)
```

`verify_mfa` é enviado sem credenciais de workspace. O desafio vale uma única vez e expira 5
minutos depois do login; um código errado responde `400`, e um desafio expirado, já usado ou com
tentativas demais responde `401` — nesse caso, faça login de novo. O login social
(`client.auth.social_login`) devolve o mesmo formato.

### Gerenciar a autenticação em dois fatores

Estas chamadas agem sobre o usuário autenticado:

```ruby
inscricao = usuario.auth.start_totp_enrollment(label: 'Meu celular')
inscricao['provisioning_uri']  # => "otpauth://totp/...": mostre como QR code
inscricao['secret']            # exibido só nesta resposta

codigos = usuario.auth.confirm_totp_enrollment(method_id: inscricao.fetch('id'), code: '123456')
codigos['recovery_codes']      # => ["ABCD-EFGH-JKMN", ...] — exibidos uma única vez

usuario.auth.mfa_methods
# => { 'methods' => [{ 'id' => 'mfa-method-id', 'type' => 'Totp', 'label' => 'Meu celular', ... }],
#      'recovery_codes_remaining' => 10 }

usuario.auth.regenerate_recovery_codes(password: ENV.fetch('ASSINAFY_PASSWORD'))
usuario.auth.delete_mfa_method('mfa-method-id', code: '123456')  # => { 'is_mfa_enabled' => false }
```

- A autenticação em dois fatores só fica ativa depois de `confirm_totp_enrollment`.
- Confirmar um novo autenticador quando já existe um **substitui** o anterior e exige
  reautenticação: `password:` ou `reauth_code:` (código do dispositivo atual ou de recuperação).
- `regenerate_recovery_codes` e `delete_mfa_method` exigem `password:` ou `code:`; sem nenhum dos
  dois, o SDK levanta `ValidationError` antes de enviar. Um código de recuperação usado como prova é
  consumido. Remover o último método também descarta os códigos de recuperação.

### Gerenciar a chave de API

```ruby
usuario.auth.create_api_key(password: ENV.fetch('ASSINAFY_PASSWORD'))  # => { 'api_key' => '...' } — exibida uma única vez
usuario.auth.get_api_key                                                # => { 'api_key' => '****...' } — mascarada
usuario.auth.delete_api_key                                             # => nil
```

Gerar uma chave nova **invalida a anterior**. Nunca exponha a chave em um front-end.

---

## 3. Conexão OAuth 2.1 (apps de marketplace)

Use OAuth quando um aplicativo age **em nome de um usuário**, com a permissão dele. Diferente da
chave de API, o token vale para **uma** workspace e carrega apenas os escopos que o usuário aprovou.
O fluxo é *authorization code* com **PKCE obrigatório** (o servidor aceita apenas `S256`).

### Escopos

| Escopo | Concede |
| --- | --- |
| `documents:read` | ler documentos, páginas, tags, signatários, assignments, atividades e entregas de webhook |
| `documents:write` | criar, alterar e excluir documentos e gerenciar seus signatários e assignments |
| `templates:read` | ler templates, páginas, papéis, campos e tags |
| `templates:write` | criar, alterar e excluir templates |
| `account:read` | ler perfil, tema, logo e endpoints de webhook da workspace |
| `webhooks:write` | criar, alterar, desativar e excluir endpoints de webhook da workspace |
| `openid` | identificar o usuário (claim `sub`) e habilitar `/oauth/userinfo` |
| `profile` | incluir o nome do usuário nas claims |
| `email` | incluir o e-mail e seu status de verificação nas claims |
| `offline_access` | receber um *refresh token* (nunca aparece no `scope` devolvido) |

Um token OAuth **nunca** alcança faturamento, ciclo de vida da conta, gerenciamento de credenciais,
segredos de assinatura de webhook ou superfícies administrativas — independentemente do escopo.

### Passo 1 — registrar o callback e redirecionar o usuário

Registre no aplicativo Assinafy uma URL de callback HTTPS. Para cada tentativa de autorização, gere
e guarde o verificador PKCE, o `state` e o emissor esperado:

```ruby
verificador = Assinafy::OAuth.generate_code_verifier
state       = Assinafy::OAuth.generate_state

session[:assinafy_code_verifier] = verificador
session[:assinafy_state]         = state
session[:assinafy_issuer]        = Assinafy::OAuth::AUTHORIZATION_SERVER # emissor desta tentativa

redirect_to Assinafy::OAuth.authorization_url(
  client_id:     ENV.fetch('ASSINAFY_CLIENT_ID'),
  redirect_uri:  'https://app.example.com/oauth/callback',
  code_verifier: verificador,
  state:         state,
  scope:         %w[documents:read documents:write offline_access]
)
```

O `code_challenge` é derivado do verificador (`S256`) — o verificador nunca vai para a URL.
`Assinafy::OAuth::AUTHORIZATION_SERVER` é o emissor de produção. No sandbox, passe
`authorization_endpoint: 'https://auth-sandbox.assinafy.com.br/oauth/authorize'` e guarde
`https://auth-sandbox.assinafy.com.br` como emissor.

### Passo 2 — validar o callback e trocar o código

```ruby
unless params[:state] == session.delete(:assinafy_state) &&
       params[:iss] == session.delete(:assinafy_issuer)
  raise 'resposta de autorização inválida'
end
raise "autorização não concedida: #{params[:error]}" if params[:error] # access_denied, invalid_scope, ...

tokens = Assinafy::Client.new.oauth.exchange_code(
  code:          params.fetch(:code),
  client_id:     ENV.fetch('ASSINAFY_CLIENT_ID'),
  code_verifier: session.delete(:assinafy_code_verifier),
  redirect_uri:  'https://app.example.com/oauth/callback'
)

tokens['access_token']   # => "..."
tokens['expires_in']     # => 3600
tokens['refresh_token']  # => presente apenas com offline_access
tokens['scope']          # => "documents:read documents:write"
```

Confira `state` e `iss` contra os valores guardados nesta tentativa **antes de qualquer outra
coisa**, inclusive num retorno com `error=` — é a proteção contra CSRF e contra respostas que não
são suas. O código vale uma vez e expira 60 segundos depois da aprovação: troque-o na hora, sem
repetir. O SDK confere localmente o formato do `code_verifier`, porque o servidor reporta um
verificador malformado como `invalid_grant`, indistinguível de um código expirado.

### Passo 3 — persistir a conexão e agir como o usuário

```ruby
access_token = tokens.fetch('access_token')

# O token só vale na workspace que o usuário escolheu.
workspace_id = Assinafy::Client.new(token: access_token).accounts.list[:data].first.fetch('id')

conexao = Conexao.create!(
  workspace_id:  workspace_id,
  scope:         tokens.fetch('scope'),
  access_token:  access_token,                    # guarde criptografado
  refresh_token: tokens['refresh_token'],         # guarde criptografado
  expires_at:    Time.now + tokens.fetch('expires_in')
)

usuario = Assinafy::Client.new(token: conexao.access_token, account_id: conexao.workspace_id)
usuario.documents.list
usuario.oauth.userinfo  # => { 'sub' => ..., 'name' => ..., 'email' => ... } (escopo openid)
```

### Renovar com rotação, uma vez por conexão

Cada renovação devolve um refresh token **novo**, válido por mais 30 dias, e aposenta o anterior: a
conexão só expira se passar 30 dias sem renovar. Reutilizar um refresh token aposentado encerra a
conexão inteira. Por isso, renove sob um lock por conexão e guarde os tokens novos atomicamente,
antes de usá-los:

```ruby
conexao.with_lock do                       # lock de linha: uma renovação por vez por conexão
  next if conexao.expires_at > Time.now + 60   # outro processo já renovou

  novos = Assinafy::Client.new.oauth.refresh(
    refresh_token: conexao.refresh_token,
    client_id:     ENV.fetch('ASSINAFY_CLIENT_ID')
  )

  conexao.update!(
    refresh_token: novos.fetch('refresh_token'),
    access_token:  novos.fetch('access_token'),
    expires_at:    Time.now + novos.fetch('expires_in')
  )
end

usuario = Assinafy::Client.new(token: conexao.access_token, account_id: conexao.workspace_id)
```

> O SDK **não renova o token automaticamente** e envia cada pedido de token uma única vez — nunca
> adicione middleware de retry à conexão. `refresh` levanta `Assinafy::Error` em vez de devolver um
> sucesso sem refresh token novo; trate como `invalid_grant`.
>
> Se a renovação falhar sem resposta clara — timeout, conexão interrompida, `5xx` —, o servidor
> pode ter trocado o token sem que a resposta chegasse. Releia o refresh token guardado: se ainda
> for o que você enviou, **nunca o reenvie**; peça ao usuário para conectar de novo. Siga em frente
> só se outro processo já tiver guardado um token diferente. Só é seguro repetir uma falha que
> comprovadamente aconteceu antes do envio: DNS, conexão recusada, handshake TLS. Num `401` da API,
> renove uma vez; se falhar, ou em `invalid_grant`, peça ao usuário para conectar de novo.

Sem `offline_access` não há refresh token: quando o access token expirar, mande o usuário pelo
fluxo de autorização de novo.

### Revogar ao desconectar

Revogue o refresh token guardado **agora** — o mais recente — e só depois apague os tokens:

```ruby
Assinafy::Client.new.oauth.revoke(
  token:           conexao.reload.refresh_token,
  client_id:       ENV.fetch('ASSINAFY_CLIENT_ID'),
  token_type_hint: 'refresh_token'
)
conexao.destroy!
```

Revogar um refresh token invalida também os access tokens emitidos a partir dele. A revogação
responde `200` inclusive para um token já aposentado, então revogar uma cópia antiga parece dar
certo enquanto a conexão continua ativa.

### Descoberta

```ruby
recurso = client.oauth.protected_resource_metadata
recurso['authorization_servers']  # => ["https://auth.assinafy.com.br"]

servidor = client.oauth.authorization_server_metadata
servidor['token_endpoint']                    # => "https://api.assinafy.com.br/v1/oauth/token"
servidor['code_challenge_methods_supported']  # => ["S256"]
```

`authorization_server_metadata` acessa outro host e é enviado sem credenciais de workspace. Ele
aceita uma URL alternativa, desde que seja HTTPS absoluta; qualquer outra levanta
`ValidationError`.

### Clientes internos de serviço

O servidor também publica o grant RFC 8693 `urn:ietf:params:oauth:grant-type:token-exchange`,
reservado a clientes confidenciais internos provisionados pela Assinafy; apps de marketplace usam
autorização com PKCE e renovação. `client.oauth.token` aceita esse grant, com `client_secret`,
`subject_token`, `subject_token_type` e `resource`. Ele não emite refresh token.

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

Num `403` de qualquer recurso, `e.context[:www_authenticate]` traz o desafio que **nomeia o escopo
faltante**: peça ao usuário para conectar de novo incluindo esse escopo, sem repetir a chamada. Um
`403` sem esse desafio indica outra workspace, o papel do usuário ou uma área que tokens OAuth não
alcançam.

---

## 4. Enviar o documento e esperar os metadados

### Upload

```ruby
documento = client.documents.upload('./contrato-acme.pdf')
documento['id']     # => "document-id"
documento['name']   # => "contrato-acme.pdf"
documento['status'] # => "uploaded"
```

Aceita um caminho, um Hash com `:file_path`, ou `:buffer` + `:file_name` para bytes em memória:

```ruby
client.documents.upload(buffer: pdf_bytes, file_name: 'contrato-acme.pdf')
```

O documento recebe o nome do arquivo enviado; para mudar, use
`client.documents.rename(documento['id'], 'Contrato Acme')`. Somente PDF, no máximo 25 MB: o SDK
confere a extensão, o tamanho e o cabeçalho `%PDF-` antes de enviar.

### Esperar o processamento

A Assinafy extrai páginas e metadados de forma assíncrona. Só é possível abrir um assignment
depois disso:

```ruby
documento = client.documents.wait_until_ready(
  documento['id'],
  max_wait_seconds:      30,
  poll_interval_seconds: 2
)
documento['status'] # => "metadata_ready"
documento['pages']  # => [{ 'id' => 'page-id', 'number' => 1, 'height' => 1651, 'width' => 1275 }]
```

Erros de rede durante a espera são tolerados; um status terminal (`failed`, `expired`,
`rejected_by_*`) ou o fim do prazo interrompe com `Assinafy::Error`.

### Alternativa: gerar a partir de um template

Um template é um PDF reutilizável com papéis e campos definidos. Configure os papéis e campos no
aplicativo Assinafy: o upload cria só um papel `Editor`, e a geração exige pelo menos um papel
`Signer`.

```ruby
template = client.templates.create('./contrato-modelo.pdf', name: 'Contrato padrão')  # até 25 MB
client.templates.list
client.templates.get(template['id'])
client.templates.update(template['id'], name: 'Contrato padrão v2')
client.templates.download_page(template['id'], 'page-id')   # bytes da imagem da página
```

Para gerar, informe uma entrada por papel, cada uma com `role_id` (de `template['roles']`) e o ID de
um signatário já existente e diferente para cada papel. A geração cria o documento e o assignment
juntos:

```ruby
papel = template.fetch('roles').find { |r| r['assignment_type'] == 'Signer' }
papeis = [{ role_id: papel.fetch('id'), id: signatario['id'],
            verification_method: 'Email', notification_methods: ['Email'] }]

client.documents.estimate_cost_from_template(template['id'], papeis)
documento = client.documents.create_from_template(
  template['id'], papeis,
  name: 'contrato-acme.pdf', message: 'Por favor, assine.', expires_at: '2099-12-31T23:59:00-03:00'
)
```

### Campos

Definições de campo reutilizáveis, usadas em assignments `collect` e templates:

```ruby
campo = client.fields.create(name: 'CPF', type: 'text', regex: '/^\d{11}$/')
client.fields.types      # tipos de campo disponíveis
client.fields.list
client.fields.validate(campo['id'], '12345678901')
client.fields.validate_multiple([{ field_id: campo['id'], value: '12345678901' }])
```

---

## 5. Signatários

Signatários pertencem à conta e podem ser reaproveitados entre documentos:

```ruby
signatario = client.signers.find_by_email('ana@example.com') ||   # paginação percorrida pelo SDK
             client.signers.create(full_name: 'Ana Silva', email: 'ana@example.com')
signatario['id'] # => "signer-id"
```

Para notificar por WhatsApp, informe `whatsapp_phone_number` (ou o alias `phone:`) em E.164. Para
**certificado digital**, informe o CPF ou CNPJ em `government_id` já na criação:

```ruby
certificado = client.signers.create(
  full_name:     'Ana Silva',
  email:         'ana@example.com',
  government_id: ENV.fetch('ASSINAFY_SIGNER_GOVERNMENT_ID')   # CPF/CNPJ real autorizado
)

# Ou num signatário existente:
client.signers.update(signatario['id'], government_id: ENV.fetch('ASSINAFY_SIGNER_GOVERNMENT_ID'))
```

`client.signers.validate_create!(payload)` valida e normaliza o corpo sem fazer requisição.

---

## 6. Métodos de verificação e notificação

Cada signatário do assignment tem um **método de verificação** (como prova a identidade antes de
assinar) e um **método de notificação** (como recebe o convite). Verificação e notificação são
**acopladas**: envie um, os dois, ou nenhum — o lado que faltar é inferido do outro. Sem nenhum dos
dois, ambos assumem `Email`.

| Verificação | Como funciona | Notificação permitida | Custo por signatário |
| --- | --- | --- | --- |
| `Email` *(padrão)* | código de uso único (OTP) por e-mail, exigido antes de assinar | `Email` | 0 crédito |
| `Whatsapp` | código de uso único (OTP) por WhatsApp; exige `whatsapp_phone_number` e plano pago | `Whatsapp` | 0,45 crédito (a notificação por WhatsApp) |
| `DigitalCertificate` | o signatário assina com o **próprio certificado ICP-Brasil (A1/A3)**, gerando uma assinatura **PAdES qualificada** | `Email` **ou** `Whatsapp` | 0,5 crédito + a notificação (0 ou 0,45) |

- Informe **exatamente um** canal em `notification_methods` (um array de um elemento).
- O custo do certificado digital aparece na estimativa com o código `SignatureDigitalCertificate`.
  Reenviar uma notificação cobra a notificação de novo.
- Os valores aceitos estão em `Assinafy::Resources::AssignmentResource::VERIFICATION_METHODS` e
  `::NOTIFICATION_METHODS`. O SDK valida enum e combinação localmente: um valor fora do enum, ou um
  par inválido, levanta `ValidationError` **antes** de a requisição sair.

### Certificado digital ICP-Brasil (A1/A3)

Exige o recurso **Certificado Digital** na conta (planos Standard e Pro), CPF ou CNPJ em
`government_id` do signatário, e que cada signatário por certificado esteja **sozinho no seu
passo**. Um CPF exige o certificado daquela pessoa (e-CPF, ou e-CNPJ que a nomeie como
representante legal); um CNPJ exige um e-CNPJ da empresa, de qualquer um de seus representantes.

---

## 7. Estimar o custo

Antes de enviar — principalmente com WhatsApp ou certificado digital:

```ruby
estimativa = client.assignments.estimate_cost(
  documento['id'],
  signers: [
    { verification_method: 'Email' },
    { verification_method: 'DigitalCertificate', notification_methods: ['Whatsapp'] }
  ]
)
estimativa['total_credits']             # => 0.95
estimativa['breakdown']                 # itens com code, quantity, unit_cost, cost
estimativa['has_sufficient_resources']  # => true
estimativa['blocking_reason']           # => nil, ou "InsufficientCredits", ...
```

Na estimativa, os signatários podem ser descritos só pelo método, sem `id`. Para um template, use
`client.documents.estimate_cost_from_template`; para um reenvio,
`client.assignments.estimate_resend_cost`.

---

## 8. Abrir o assignment

Um assignment é o convite para assinar um documento. Todo assignment exige ao menos um signatário.

**`virtual`** — sem campos posicionados; o signatário aceita o documento inteiro.

```ruby
assignment = client.assignments.create(
  documento['id'],
  method:  'virtual',
  signers: [
    { id: signatario['id'],  verification_method: 'Email', notification_methods: ['Email'], step: 1 },
    { id: certificado['id'], verification_method: 'DigitalCertificate', notification_methods: ['Email'], step: 2 }
  ],
  message:        'Por favor, assine o contrato em anexo.',
  expires_at:     '2099-12-31T23:59:00-03:00',
  copy_receivers: []                       # IDs de signatários que só recebem cópia
)

assignment['signing_urls']
# => [{ 'signer_id' => 'signer-id', 'url' => 'https://.../sign/...' }, ...]
```

**`collect`** — campos posicionados página a página, além da lista de signatários:

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

O SDK aceita `signers: ['id1', 'id2']` (IDs puros), `signers: [{ id: ... }]` (descritores completos)
e o formato legado `signer_ids:`. Tudo é normalizado para o corpo que a API espera.

### Passos e prazos

- `step` define a ordem: todos do passo 1 assinam antes do passo 2; passos iguais assinam em
  paralelo. Se informado para um signatário, informe para todos, em uma sequência contínua iniciada
  em 1. Omita para assinatura simultânea.
- Cada signatário é notificado quando seu passo é ativado: o passo 1 na criação, os seguintes
  quando todos do passo anterior concluírem.
- Um signatário por certificado digital fica sozinho no seu passo.
- `expires_at` deve ser ISO 8601 com fuso horário e estar pelo menos uma hora no futuro.

Gerenciar depois de criado:

```ruby
client.assignments.estimate_resend_cost(documento['id'], assignment['id'], signatario['id'])
client.assignments.resend_notification(documento['id'], assignment['id'], signatario['id'])
client.assignments.reset_expiration(documento['id'], assignment['id'], '2099-01-31T23:59:00-03:00')
client.assignments.whatsapp_notifications(documento['id'], assignment['id'])
client.assignments.list   # assignments da conta
```

### Atalho: tudo em uma chamada

```ruby
resultado = client.upload_and_request_signatures(
  source:  './contrato-acme.pdf',
  signers: [{ full_name: 'Ana Silva', email: 'ana@example.com' }],
  message: 'Por favor, assine o contrato em anexo.'
)

resultado[:document]['id']    # => "document-id"
resultado[:assignment]['id']  # => "assignment-id"
resultado[:signer_ids]        # => ["signer-id"]
```

O helper faz upload, espera o processamento, cria os signatários (incluindo `government_id`, quando
informado) e abre um assignment `virtual`. Ele valida o payload inteiro **antes** de enviar
qualquer coisa, então um `expires_at` malformado não deixa um documento órfão.

> **Não é transacional.** Se uma chamada posterior falhar, o documento enviado e os signatários
> já criados continuam existindo. Em caso de erro, `e.context[:document]` e
> `e.context[:signer_ids]` trazem o que foi criado, para você limpar.

---

## 9. A experiência do signatário

O signatário recebe o link de acesso pelo canal de notificação. As chamadas abaixo usam o **código
de acesso do signatário** (enviado como parâmetro de query `signer-access-code`), não suas
credenciais de workspace — o SDK remove `X-Api-Key`/`Authorization` delas. Um cliente sem
credenciais basta:

```ruby
signatario_client = Assinafy::Client.new
codigo = 'codigo-de-acesso-do-link-de-assinatura'

# 1. Carregar o documento e aceitar os termos
dados = signatario_client.signers.self_data(signer_access_code: codigo)
signatario_client.signers.accept_terms(signer_access_code: codigo) unless dados['has_accepted_terms']
doc = signatario_client.assignments.signer_document(signer_access_code: codigo, has_accepted_terms: true)

# 2. Confirmar a identidade
signatario_client.signers.confirm_data(
  doc['id'], { full_name: 'Ana Silva', government_id: '00000000000' },
  signer_access_code: codigo
)

# 3. Verificar o código de uso único (OTP) recebido por e-mail ou WhatsApp
signatario_client.signers.verify_email(verification_code: '123456', signer_access_code: codigo)

# 4. Enviar a imagem da assinatura (PNG)
signatario_client.signers.upload_signature(
  File.binread('assinatura.png'), signer_access_code: codigo, type: 'signature'
)
```

`verify_email` envia o código de qualquer canal (`POST /verify`). Em seguida, assine.

Assignment **virtual**:

```ruby
signatario_client.signer_documents.sign_multiple([doc['id']], signer_access_code: codigo)
```

Assignment **collect** — envie cada item posicionado:

```ruby
itens = doc.fetch('assignment').fetch('items').map do |item|
  {
    item_id:  item.fetch('id'),
    field_id: item.dig('field', 'id'),
    page_id:  item.dig('page', 'id'),
    value:    'Aceito'
  }
end

signatario_client.assignments.sign(doc['id'], doc.dig('assignment', 'id'), itens, signer_access_code: codigo)
```

O SDK converte as chaves `item_id`/`field_id`/`page_id` para o `itemId`/`fieldId`/`pageId` que a API
espera.

Recusar:

```ruby
signatario_client.assignments.decline(
  doc['id'], doc.dig('assignment', 'id'),
  decline_reason: 'Valores divergentes da proposta',
  signer_access_code: codigo
)
# Vários documentos de uma vez:
signatario_client.signer_documents.decline_multiple([doc['id']], decline_reason: 'Não', signer_access_code: codigo)
```

### Signatários com certificado A1/A3

O signatário por certificado digital conclui a assinatura no fluxo hospedado da Assinafy, aberto
pelo link de `assignment['signing_urls']`: ele aceita os termos, confirma os dados e assina com o
certificado A1 ou A3 pela extensão de navegador Web PKI. O endpoint comum de assinatura rejeita
signatários por certificado, e o SDK não envolve o handshake Web PKI
(`/signers/certificate/start`, `/signers/certificate/complete`), cujos esquemas não fazem parte do
contrato OpenAPI. Concluído o fluxo, o artefato `pades` traz a assinatura PAdES qualificada.

---

## 10. Webhooks: endpoints e verificação de assinatura

Para acompanhar sem polling, registre um **endpoint de webhook**. Uma conta pode ter 1 endpoint, ou
até 3 em planos pagos; cada um tem sua própria URL (distinta das demais), lista de eventos e
configuração de assinatura. Todo endpoint ativo inscrito num evento o recebe.

### Gerenciar endpoints

```ruby
client.webhooks.list_event_types   # => [{ 'id' => 'document_ready', 'description' => '...' }, ...]

endpoint = client.webhooks.create_endpoint(
  url:             'https://app.example.com/webhooks/assinafy',
  email:           'ops@example.com',          # avisos de falha de entrega
  events:          %w[document_ready signer_signed_document signer_rejected_document],
  name:            'ERP',
  signing_enabled: true
)
endpoint['id'] # => "webhook-endpoint-id"

client.webhooks.list_endpoints                              # do mais antigo ao mais novo
client.webhooks.get_endpoint('webhook-endpoint-id')
client.webhooks.update_endpoint('webhook-endpoint-id', is_active: false)   # só os campos enviados
client.webhooks.delete_endpoint('webhook-endpoint-id')                     # => nil, libera a vaga
```

- `create_endpoint` exige `url`, `email` e `events`; `name`, `is_active` (padrão `true`) e
  `signing_enabled` (padrão `false`) são opcionais. Chaves desconhecidas levantam
  `ValidationError` localmente.
- Criar além do limite do plano responde `403`; uma URL já usada por outro endpoint responde `400`.
- Em `update_endpoint`, `signing_enabled: true` gera um segredo se o endpoint não tiver um (e mantém
  o atual se tiver); `signing_enabled: false` descarta o segredo.

### Segredo de assinatura

```ruby
segredo = client.webhooks.endpoint_secret('webhook-endpoint-id')
segredo['secret'] # => "whsec_..."

novo = client.webhooks.rotate_endpoint_secret('webhook-endpoint-id')
```

A rotação vale imediatamente: entregas posteriores são assinadas só com o segredo novo, então
atualize o receptor na mesma hora. Ler e rotacionar o segredo **não** está disponível para
aplicativos OAuth — use uma chave de API ou um token de sessão de usuário. Com assinatura
desativada, ambos respondem `400`.

### O contrato de entrega

| Propriedade | Valor |
| --- | --- |
| Requisição | `POST`, `Content-Type: application/json` |
| `webhook-id` | ID da mensagem, igual em todas as tentativas do mesmo evento para o mesmo endpoint — use para deduplicar |
| `webhook-timestamp` | horário Unix (segundos) da tentativa |
| `webhook-signature` | só com assinatura ativa: entradas `v1,<base64>` separadas por espaço |
| Sucesso | qualquer resposta `2xx` |
| Tentativas | até 2 por evento, com 3 segundos de intervalo |
| Circuit breaker | depois de 10 eventos consecutivos com falha, a entrega pausa e só uma amostra de eventos é testada até um dar certo |

Responda `2xx` rapidamente e processe em segundo plano. Para forçar uma nova entrega, use
`retry_dispatch`:

```ruby
client.webhooks.list_dispatches(endpoint_id: 'webhook-endpoint-id', delivered: false, per_page: 20)
client.webhooks.retry_dispatch('dispatch-id')
```

O corpo segue o envelope `{ id, event, message, payload, origin, created_at, subject, object,
account_id }`. `subject` é quem agiu e `object` é a entidade afetada, cada um com uma propriedade
`type` (`User`, `Signer`, `Account`, `Document` ou `Template`). Os horários do corpo são Unix em
segundos.

### Verificar a assinatura

As assinaturas seguem a especificação [Standard Webhooks](https://www.standardwebhooks.com): um
HMAC-SHA256 sobre `"{webhook-id}.{webhook-timestamp}.{corpo bruto}"`, com a chave obtida
decodificando em base64 a parte do segredo depois de `whsec_`. `verify_delivery` confere essa
assinatura em tempo constante e rejeita horários a mais de 5 minutos do relógio local:

```ruby
verificador = Assinafy::Support::WebhookVerifier.new(ENV.fetch('ASSINAFY_WEBHOOK_SECRET'))
# ou client.webhook_verifier, que usa o webhook_secret do cliente

verificador.verify_delivery(corpo_bruto, headers)                 # => true / false
verificador.verify_delivery(corpo_bruto, headers, tolerance: 120) # janela em segundos
```

`headers` pode ser o `request.headers` do Rails, o `env` do Rack (`HTTP_WEBHOOK_ID`) ou um Hash
simples. O método devolve `false` — nunca levanta — para segredo ausente ou malformado, cabeçalho
faltando, assinatura errada ou horário fora da janela. Sempre passe o corpo **bruto**, exatamente
como recebido, nunca o JSON reserializado. Com mais de um endpoint, cada um tem seu segredo.

Receptor Rails:

```ruby
class AssinafyWebhooksController < ActionController::API
  VERIFICADOR = Assinafy::Support::WebhookVerifier.new(ENV.fetch('ASSINAFY_WEBHOOK_SECRET'))

  def create
    corpo = request.raw_post
    return head(:unauthorized) unless VERIFICADOR.verify_delivery(corpo, request.headers)

    webhook_id = request.headers['webhook-id']
    return head(:ok) if EventoAssinafy.exists?(webhook_id: webhook_id)   # já processado

    evento = VERIFICADOR.extract_event(corpo)
    EventoAssinafy.create!(webhook_id: webhook_id, tipo: VERIFICADOR.event_type(evento), corpo: corpo)
    ProcessarEventoAssinafyJob.perform_later(webhook_id)
    head :ok
  end
end
```

Receptor Rack (Sinatra):

```ruby
post '/webhooks/assinafy' do
  corpo = request.body.read
  halt 401 unless VERIFICADOR.verify_delivery(corpo, request.env)

  evento = VERIFICADOR.extract_event(corpo)
  case VERIFICADOR.event_type(evento)
  when 'signer_signed_document' then processar(VERIFICADOR.event_object(evento))  # o Document
  when 'document_ready'         then baixar_assinado(VERIFICADOR.event_object(evento)['id'])
  end

  200
end
```

`extract_event` devolve `nil` para JSON inválido; `event_type`, `event_payload`, `event_object` e
`event_subject` leem os campos do envelope.

O método `verify(corpo, assinatura_hex)` continua disponível apenas para receptores cujo **próprio
gateway** assina o corpo com um HMAC-SHA256 em hexadecimal e um segredo compartilhado.

### Assinatura legada

`client.webhooks.register`, `#get` e `#inactivate` (`/webhooks/subscriptions`) continuam funcionando e
agem sobre o endpoint **mais antigo** da conta. `register` aceita só `url`, `email`, `events` e
`is_active`; outras chaves levantam `ValidationError`. Prefira as operações de endpoint.

---

## 11. Andamento, download e verificação

```ruby
client.documents.signing_progress(documento['id'])
# => { signed: 1, total: 3, pending: 2, percentage: 33.33 }

client.documents.fully_signed?(documento['id'])  # => false
client.documents.activities(documento['id'])     # trilha completa de eventos, com origin (ip, user-agent)
```

| Artefato | Conteúdo |
| --- | --- |
| `original` | O PDF enviado, como recebido |
| `certificated` | O documento assinado, com a certificação da plataforma |
| `certificate-page` | Apenas a página de certificação |
| `pades` | Assinaturas ICP-Brasil dos signatários + caixa de certificação — só em documentos com signatários por certificado digital |
| `bundle` | Zip com `original`, `certificated` e `certificate-page`, mais o `pades` quando houver |

```ruby
File.binwrite('assinado.pdf', client.documents.download(documento['id'], 'certificated'))
File.binwrite('pades.pdf',    client.documents.download(documento['id'], 'pades'))
File.binwrite('pacote.zip',   client.documents.download(documento['id'], 'bundle'))
```

A verificação pública confere um documento assinado pelo hash da assinatura, sem autenticação:

```ruby
verificacao = Assinafy::Client.new.documents.verify('hash-da-assinatura')
verificacao['is_valid']        # => true
verificacao['agreement_code']  # código impresso no certificado do documento
```

Ela devolve o resultado da Assinafy; não valida independentemente a assinatura do PDF nem a
cadeia de certificação.

---

## 12. Organizar e limpar

```ruby
tag = client.tags.create(name: 'Contratos 2026', color: '2072b9')
client.documents.append_tags(documento['id'], [tag['id']])
client.documents.replace_tags(documento['id'], [tag['id']])
client.documents.detach_tag(documento['id'], tag['id'])

# Documentos que carregam TODAS as tags informadas (o SDK junta o Array com vírgulas):
client.documents.list(tags: [tag['id'], 'outra-tag-id'])

client.documents.rename(documento['id'], 'Contrato Acme — assinado')
```

Apague só o que a sua aplicação criou, e só depois de concluir o que depende do recurso. Alguns
respondem `409` enquanto ainda estão em processamento ou referenciados. Mantenha signatários e
templates compartilhados.

```ruby
client.documents.delete(documento['id'])
client.signers.delete(signatario['id'])
client.webhooks.delete_endpoint('webhook-endpoint-id')
client.tags.delete(tag['id'], force: true)   # force desvincula de documentos e templates
```

---

## 13. Erros

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

Toda exceção do SDK deriva de `Assinafy::Error` e carrega um `#context` com detalhes para
depuração. `ApiError` trata as duas formas de corpo de erro da API — o erro de framework
(`{"name":..., "code":..., "status":...}`) e o envelope de aplicação
(`{"status":..., "data":null, "message":...}`) — inclusive quando um `200` traz um `status`
interno de falha. Num `403`, `e.context[:www_authenticate]` traz o desafio OAuth, quando houver.

---

## 14. Paginação

Os métodos `*.list*` devolvem `{ data: [...], meta: { ... } }` quando a API envia cabeçalhos de
paginação:

```ruby
pagina = client.documents.list(page: 1, per_page: 50)
pagina[:data]  # => [Documento, ...]
pagina[:meta]  # => { current_page: 1, per_page: 50, total: 128, last_page: 3 }
```

O `per_page:` em estilo Ruby é convertido para o parâmetro `per-page` documentado. Valores acima
do máximo são limitados pelo servidor. Endpoints que não paginam (por exemplo `accounts.list`)
devolvem só `{ data: [...] }`, sem `meta`.

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

## 15. Recursos do cliente

| Acessor | Cobre |
| --- | --- |
| `client.auth` | login, autenticação em dois fatores, login social, senha, chaves de API |
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
| `client.webhooks` | endpoints, segredos de assinatura, entregas, reenvio |
| `client.webhook_verifier` | verificação de assinatura das entregas recebidas |

KPIs: `client.users.stats` e `client.accounts.stats` aceitam `granularity:` (`'monthly'` ou
`'daily'`) e `month:` (`'AAAA-MM'`), validados localmente:

```ruby
client.accounts.stats(granularity: 'daily', month: '2026-06')
```

`client.faraday_connection` expõe a conexão Faraday para inspeção em testes. Nunca adicione
middleware que repita requisições: pedidos de token não podem ser reenviados.

---

## 16. Assinaturas RBS

`sig/assinafy.rbs` acompanha a gem, então consumidores que usam RBS têm as assinaturas
publicadas. [`spec/rbs_signature_spec.rb`](spec/rbs_signature_spec.rb) garante que todo método
público de recurso, do `Client` e de `Assinafy::OAuth` tenha uma assinatura declarada.

---

## Documentação

- **[README.en.md](README.en.md)** — referência completa por recurso, em inglês
- [docs/API_REFERENCE.md](docs/API_REFERENCE.md) — referência por operação
- [CHANGELOG.md](CHANGELOG.md) — histórico de versões
- [Documentação da API](https://api.assinafy.com.br/v1/docs)

## Desenvolvimento e testes

```bash
bundle exec rake spec
bundle exec rubocop
bundle exec bundler-audit check --update
rbs -I sig validate
ruby scripts/check_api_contract.rb
```

A [suíte sandbox](spec/integration/live_sandbox_spec.rb) fica fora da execução padrão.
Veja os [pré-requisitos e variáveis](README.en.md#live-integration-tests), incluindo um template
com papel `Signer` para testar a geração. Os testes enviam e-mails e removem os recursos criados.

## Licença

Distribuído sob a licença [MIT](LICENSE).
