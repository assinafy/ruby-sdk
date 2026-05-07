# frozen_string_literal: true

RSpec.describe Assinafy::Client do
  describe '.new' do
    it 'can be created without credentials for public and authentication endpoints' do
      client = described_class.new
      expect(client.auth).to be_a(Assinafy::Resources::AuthResource)
    end

    it 'accepts api_key and exposes all resource accessors' do
      client = described_class.new(api_key: 'k', account_id: 'acc')

      expect(client.auth).to            be_a(Assinafy::Resources::AuthResource)
      expect(client.documents).to       be_a(Assinafy::Resources::DocumentResource)
      expect(client.signers).to         be_a(Assinafy::Resources::SignerResource)
      expect(client.signer_documents).to be_a(Assinafy::Resources::SignerDocumentResource)
      expect(client.assignments).to     be_a(Assinafy::Resources::AssignmentResource)
      expect(client.webhooks).to        be_a(Assinafy::Resources::WebhookResource)
      expect(client.templates).to       be_a(Assinafy::Resources::TemplateResource)
      expect(client.fields).to          be_a(Assinafy::Resources::FieldResource)
      expect(client.webhook_verifier).to be_a(Assinafy::Support::WebhookVerifier)
    end

    it 'accepts legacy token credentials' do
      client = described_class.new(token: 't', account_id: 'acc')
      expect(client.documents).to be_a(Assinafy::Resources::DocumentResource)
    end

    it 'sends X-Api-Key header when api_key is provided' do
      client = described_class.new(api_key: 'my-key', account_id: 'acc')
      expect(client.faraday_connection.headers['X-Api-Key']).to eq('my-key')
    end

    it 'sends Bearer Authorization header when only token is provided' do
      client = described_class.new(token: 'legacy', account_id: 'acc')
      expect(client.faraday_connection.headers['Authorization']).to eq('Bearer legacy')
    end

    it 'strips trailing slash from base_url' do
      client = described_class.new(
        api_key:  'k',
        account_id: 'acc',
        base_url: 'https://sandbox.assinafy.com.br/v1/'
      )
      expect(client.faraday_connection.url_prefix.to_s.chomp('/')).to eq('https://sandbox.assinafy.com.br/v1')
    end
  end

  describe '.create' do
    it 'builds a configured client from positional args' do
      client = described_class.create('k', 'acc', webhook_secret: 's')
      expect(client.documents).to be_a(Assinafy::Resources::DocumentResource)
    end
  end

  describe '.from_config' do
    it 'accepts string-keyed hashes' do
      client = described_class.from_config('api_key' => 'k', 'account_id' => 'acc', 'webhook_secret' => 's')
      expect(client.documents).to be_a(Assinafy::Resources::DocumentResource)
    end

    it 'accepts symbol-keyed hashes' do
      client = described_class.from_config(api_key: 'k', account_id: 'acc')
      expect(client.documents).to be_a(Assinafy::Resources::DocumentResource)
    end
  end
end
