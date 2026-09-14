# SDK Ruby da Assinafy

*Português · [Read in English](README.en.md)*

[![CI](https://github.com/assinafy/ruby-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/assinafy/ruby-sdk/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/assinafy.svg)](https://rubygems.org/gems/assinafy)

SDK Ruby para a [API Assinafy v1](https://api.assinafy.com.br/v1/docs) — plataforma brasileira de
assinatura eletrônica de documentos.

O SDK expõe **todas** as operações da API Assinafy v1 e o ciclo de vida completo de templates
suportado. O [`spec/api_coverage_spec.rb`](spec/api_coverage_spec.rb), versionado no repositório,
valida que cada rota mapeia de forma única para um método público do SDK.

> **Referência completa em inglês.** Este documento cobre instalação, autenticação e os fluxos
> principais. O manual de referência por recurso está em **[README.en.md](README.en.md)**, e a
> referência por operação em [docs/API_REFERENCE.md](docs/API_REFERENCE.md).

## Requisitos

- Ruby 3.2+ (suporte mantido: 3.3+; 3.2 é compatibilidade legada/EOL)
- Bundler

## Instalação

Do RubyGems.org:

```ruby
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

Você vai precisar de um personal access token com escopo `read:packages`, configurado via:

```bash
bundle config https://rubygems.pkg.github.com/assinafy USUARIO:TOKEN
```

## Início rápido

```ruby
require 'assinafy'

client = Assinafy::Client.new(
  api_key:    ENV.fetch('ASSINAFY_API_KEY'),
  account_id: ENV.fetch('ASSINAFY_ACCOUNT_ID')
)

documento = client.documents.upload({ file_path: './contrato.pdf' })
signatario = client.signers.create(full_name: 'Ana Silva', email: 'ana@exemplo.com.br')

assignment = client.assignments.create(
  documento['id'],
  method:  'virtual',
  signers: [{ id: signatario['id'] }],
  message: 'Por favor, assine o contrato em anexo.'
)

puts assignment['id']
```

## Configuração

```ruby
client = Assinafy::Client.new(
  api_key:        'sua-chave-de-api',
  token:          nil,
  account_id:     'seu-account-id',
  base_url:       'https://api.assinafy.com.br/v1',
  webhook_secret: nil,
  timeout:        30,
  logger:         Logger.new($stdout)
)
```

- `api_key:` envia `X-Api-Key` (preferido).
- `token:` envia `Authorization: Bearer ...` (token de sessão legado).
- Configure **exatamente uma** credencial. Se as duas forem informadas, o SDK envia apenas
  `X-Api-Key`.
- Um cliente também pode ser criado **sem credenciais**, para autenticação e endpoints
  públicos/de signatário.
- `base_url:` precisa ser uma URL `http`/`https` absoluta. Qualquer outra coisa — um host sem
  esquema, um caminho relativo, ou outro esquema — levanta `Assinafy::ValidationError` em vez de
  anexar suas credenciais a ela. Barra ao final é removida.
- Métodos com escopo de conta documentam uma sobrescrita de conta por chamada, para tenants com
  múltiplos workspaces.
- Forneça um `logger:` compatível com `Logger` para observar as mensagens de ciclo de vida de
  upload, assignment e webhook.
- As requisições enviam `User-Agent: Assinafy-Ruby-SDK/v<Assinafy::VERSION>`; o sufixo sempre segue
  a versão da gem.

`Client.from_config(hash)` aceita hashes com chaves string ou símbolo (por exemplo, YAML já
interpretado).

## Métodos de verificação do signatário

Definidos por signatário ao criar o assignment. O método de verificação e o de notificação são
**acoplados**: envie um, os dois ou nenhum — o lado que faltar é inferido. Sem nenhum dos dois, ambos
assumem `Email`.

| Método | Como funciona | Custo por signatário |
| --- | --- | --- |
| `Email` *(padrão)* | Código de uso único (OTP) por e-mail, exigido antes de assinar | Gratuito |
| `Whatsapp` | Código de uso único (OTP) por WhatsApp | Verificação gratuita; notificação 0,45 crédito, só em planos pagos |
| `DigitalCertificate` | O signatário assina com o **próprio certificado ICP-Brasil (A1/A3)**, pela extensão de navegador Web PKI, gerando uma assinatura **PAdES qualificada** | 2 créditos |

Combinações permitidas: `Email` → notifica por `Email`; `Whatsapp` → notifica por `Whatsapp`;
`DigitalCertificate` → notifica por `Email` **ou** `Whatsapp`. Apenas um método de notificação por
signatário.

### Certificado digital ICP-Brasil

Exige o recurso **Certificado Digital** na conta (planos Standard e Pro), CPF ou CNPJ em
`government_id` do signatário, e exatamente **um signatário por certificado naquele passo**. Um CPF
exige o certificado daquela pessoa (e-CPF, ou e-CNPJ que a nomeie como representante legal); um CNPJ
exige um e-CNPJ da empresa.

Use `client.assignments.estimate_cost(...)` antes de enviar: a assinatura por certificado custa 2
créditos por signatário, além do custo da notificação escolhida.

Antes de abrir o assignment, o signatário precisa confirmar os dados de identidade e aceitar os
termos. O endpoint comum de assinatura **rejeita** signatários por certificado — a assinatura deles é
produzida por um handshake de dois passos com a extensão Web PKI:

```
POST /v1/signers/certificate/start     → data.token   (token da operação Web PKI)
        ↓  o navegador assina o token com o certificado do signatário
POST /v1/signers/certificate/complete  → data.signerName
```

> Essas duas rotas são extensões implantadas **somente em produção**: o sandbox não as expõe e elas
> não constam do documento OpenAPI publicado.

Concluído o fluxo, baixar o artefato `pades` devolve a assinatura PAdES qualificada.

## Trilha de atividades e artefatos

As atividades de um documento devolvem todos os eventos registrados, cada um com um snapshot do
`payload` do evento e a `origin` da requisição (`ip`, `user-agent`).

| Artefato | Conteúdo |
| --- | --- |
| `original` | O PDF enviado, como recebido |
| `certificated` | O documento assinado, com a certificação da plataforma |
| `certificate-page` | Apenas a página de certificação |
| `pades` | Assinaturas ICP-Brasil dos signatários + caixa de certificação — só existe em documentos que tiveram signatários por certificado digital |
| `bundle` | Zip com `original`, `certificated` e `certificate-page`, mais o `pades` quando houver |

A verificação pública confere um documento assinado pelo hash da assinatura, sem autenticação.

## Recursos do cliente

```ruby
client.auth          client.accounts    client.users       client.documents
client.signers       client.assignments client.templates   client.tags
client.fields        client.webhooks    client.signer_documents
```

## Ambientes

| | |
| --- | --- |
| Produção | `https://api.assinafy.com.br/v1` |
| Sandbox | `https://sandbox.assinafy.com.br/v1` |

O sandbox é gratuito e espelha a produção para testar a integração de ponta a ponta — com a exceção
das rotas de certificado digital, que existem apenas em produção.

## Assinaturas RBS

`sig/assinafy.rbs` acompanha a gem, então consumidores que usam RBS têm as assinaturas publicadas.
Desde a remoção do Steep, elas não são mais verificadas contra a implementação a cada build e podem
divergir — veja o [CHANGELOG](CHANGELOG.md).

## Documentação

- **[README.en.md](README.en.md)** — referência completa por recurso, em inglês
- [docs/API_REFERENCE.md](docs/API_REFERENCE.md) — referência por operação
- [Documentação da API](https://api.assinafy.com.br/v1/docs)

## Licença

Distribuído sob a licença [MIT](LICENSE).
