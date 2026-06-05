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
      expect(client.tags).to            be_a(Assinafy::Resources::TagResource)
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
        api_key:    'k',
        account_id: 'acc',
        base_url:   'https://sandbox.assinafy.com.br/v1/'
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

  describe '#upload_and_request_signatures' do
    let(:base_url) { 'https://api.assinafy.com.br/v1' }
    let(:client)   { described_class.new(api_key: 'test-key', account_id: 'acc', base_url: base_url) }
    let(:signers)  { [{ full_name: 'Audit Bill', email: 'bill@febacapital.com' }] }

    def stub_upload
      stub_request(:post, "#{base_url}/accounts/acc/documents")
        .to_return(api_envelope({ 'id' => 'doc-1', 'status' => 'uploaded' }))
    end

    def stub_ready
      stub_request(:get, "#{base_url}/documents/doc-1")
        .to_return(api_envelope({ 'id' => 'doc-1', 'status' => 'metadata_ready' }))
    end

    def stub_signers
      stub_request(:post, "#{base_url}/accounts/acc/signers")
        .to_return(api_envelope({ 'id' => 'signer-1', 'full_name' => 'Audit Bill' }))
    end

    def stub_assignment
      stub_request(:post, "#{base_url}/documents/doc-1/assignments")
        .to_return(api_envelope({ 'id' => 'asg-1', 'method' => 'virtual' }))
    end

    it 'returns the document, assignment, and created signer IDs' do
      stub_upload
      stub_ready
      stub_signers
      stub_assignment

      result = client.upload_and_request_signatures(
        source: { buffer: '%PDF-1.4', file_name: 'contract.pdf' }, signers: signers, message: 'Please sign'
      )

      expect(result[:document]['id']).to   eq('doc-1')
      expect(result[:assignment]['id']).to eq('asg-1')
      expect(result[:signer_ids]).to       eq(['signer-1'])
    end

    it 'posts the virtual assignment body with signer refs and message' do
      stub_upload
      stub_ready
      stub_signers
      stub_assignment

      client.upload_and_request_signatures(
        source: { buffer: '%PDF-1.4', file_name: 'contract.pdf' }, signers: signers, message: 'Please sign'
      )

      expect(
        a_request(:post, "#{base_url}/documents/doc-1/assignments").with(
          body: hash_including('method' => 'virtual', 'signers' => [{ 'id' => 'signer-1' }], 'message' => 'Please sign')
        )
      ).to have_been_made
    end

    it 'creates a signer for each entry via the account signers endpoint' do
      stub_upload
      stub_ready
      stub_signers
      stub_assignment

      client.upload_and_request_signatures(
        source: { buffer: '%PDF-1.4', file_name: 'contract.pdf' }, signers: signers
      )

      expect(
        a_request(:post, "#{base_url}/accounts/acc/signers")
          .with(body: hash_including('full_name' => 'Audit Bill', 'email' => 'bill@febacapital.com'))
      ).to have_been_made
    end

    it 'raises ValidationError when no signers are given' do
      expect do
        client.upload_and_request_signatures(source: { buffer: '%PDF-1.4', file_name: 'contract.pdf' }, signers: [])
      end.to raise_error(Assinafy::ValidationError)
    end

    it 'does not fetch document details when wait_for_ready is false' do
      stub_upload
      ready = stub_ready
      stub_signers
      stub_assignment

      client.upload_and_request_signatures(
        source: { buffer: '%PDF-1.4', file_name: 'contract.pdf' }, signers: signers, wait_for_ready: false
      )

      expect(ready).not_to have_been_requested
    end
  end
end
