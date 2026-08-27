# frozen_string_literal: true

RSpec.describe Assinafy::Client do
  describe '.new' do
    it 'can be created without credentials for public and authentication endpoints' do
      client = described_class.new
      expect(client.auth).to be_a(Assinafy::Resources::AuthResource)
    end

    it 'accepts api_key and exposes all resource accessors' do
      client = described_class.new(api_key: 'k', account_id: 'acc')

      aggregate_failures do
        expect(client.auth).to             be_a(Assinafy::Resources::AuthResource)
        expect(client.accounts).to         be_a(Assinafy::Resources::AccountResource)
        expect(client.users).to            be_a(Assinafy::Resources::UserResource)
        expect(client.documents).to        be_a(Assinafy::Resources::DocumentResource)
        expect(client.signers).to          be_a(Assinafy::Resources::SignerResource)
        expect(client.signer_documents).to be_a(Assinafy::Resources::SignerDocumentResource)
        expect(client.assignments).to      be_a(Assinafy::Resources::AssignmentResource)
        expect(client.webhooks).to         be_a(Assinafy::Resources::WebhookResource)
        expect(client.templates).to        be_a(Assinafy::Resources::TemplateResource)
        expect(client.fields).to           be_a(Assinafy::Resources::FieldResource)
        expect(client.tags).to             be_a(Assinafy::Resources::TagResource)
        expect(client.webhook_verifier).to be_a(Assinafy::Support::WebhookVerifier)
      end
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

    it 'sends the exact SDK User-Agent on production and sandbox requests' do
      clients = [
        described_class.new(api_key: 'k', account_id: 'acc'),
        described_class.new(
          api_key: 'k', account_id: 'acc', base_url: 'https://sandbox.assinafy.com.br/v1'
        )
      ]

      clients.each do |configured_client|
        base = configured_client.faraday_connection.url_prefix.to_s.chomp('/')
        request = stub_request(:get, "#{base}/signers/self")
                  .with(
                    query:   hash_including('signer-access-code' => 'code'),
                    headers: { 'User-Agent' => "Assinafy-Ruby-SDK/v#{Assinafy::VERSION}" }
                  ) do |sent|
          !sent.headers.key?('X-Api-Key') && !sent.headers.key?('Authorization')
        end.to_return(api_envelope({ 'id' => 'signer-1' }))

        configured_client.signers.self_data(signer_access_code: 'code')

        expect(request).to have_been_requested
      end
    end

    it 'falls back to the bearer token when api_key is blank' do
      client = described_class.new(api_key: '  ', token: 'legacy')
      expect(client.faraday_connection.headers['Authorization']).to eq('Bearer legacy')
    end

    it 'rejects invalid configuration values' do
      expect { described_class.new(base_url: '') }.to raise_error(Assinafy::ValidationError)
      expect { described_class.new(base_url: false) }.to raise_error(Assinafy::ValidationError)
      expect { described_class.new(timeout: 0) }.to raise_error(Assinafy::ValidationError)
      expect { described_class.new(timeout: 1.9) }.to raise_error(Assinafy::ValidationError)
    end

    it 'strips trailing slash from base_url' do
      client = described_class.new(
        api_key:    'k',
        account_id: 'acc',
        base_url:   'https://sandbox.assinafy.com.br/v1/'
      )
      expect(client.faraday_connection.url_prefix.to_s.chomp('/')).to eq('https://sandbox.assinafy.com.br/v1')
    end

    it 'applies the configured timeout to reads and connections' do
      client = described_class.new(timeout: 12)

      expect(client.faraday_connection.options.timeout).to eq(12)
      expect(client.faraday_connection.options.open_timeout).to eq(12)
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

    it 'accepts a positive timeout encoded as a string' do
      client = described_class.from_config(timeout: '45')
      expect(client.faraday_connection.options.timeout).to eq(45)
    end

    it 'rejects a non-Hash or invalid timeout' do
      expect { described_class.from_config(nil) }.to raise_error(Assinafy::ValidationError)
      expect { described_class.from_config(timeout: 'not-a-number') }.to raise_error(Assinafy::ValidationError)
      expect { described_class.from_config(timeout: false) }.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#upload_and_request_signatures' do
    let(:base_url) { 'https://api.assinafy.com.br/v1' }
    let(:client)   { described_class.new(api_key: 'test-key', account_id: 'acc', base_url: base_url) }
    let(:signers)  { [{ full_name: 'Example Signer', email: 'signer@example.com' }] }
    let(:pdf_source) do
      { buffer: "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n".b, file_name: 'contract.pdf' }
    end

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
        .to_return(api_envelope({ 'id' => 'signer-1', 'full_name' => 'Example Signer' }))
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
        source: pdf_source, signers: signers, message: 'Please sign'
      )

      expect(result[:document]['id']).to eq('doc-1')
      expect(result[:document]['status']).to eq('metadata_ready')
      expect(result[:assignment]['id']).to eq('asg-1')
      expect(result[:signer_ids]).to       eq(['signer-1'])
    end

    it 'posts the virtual assignment body with signer refs and message' do
      stub_upload
      stub_ready
      stub_signers
      stub_assignment

      client.upload_and_request_signatures(
        source: pdf_source, signers: signers, message: 'Please sign'
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
        source: pdf_source, signers: signers
      )

      expect(
        a_request(:post, "#{base_url}/accounts/acc/signers")
          .with(body: hash_including('full_name' => 'Example Signer', 'email' => 'signer@example.com'))
      ).to have_been_made
    end

    it 'raises ValidationError when no signers are given' do
      expect do
        client.upload_and_request_signatures(source: pdf_source, signers: [])
      end.to raise_error(Assinafy::ValidationError)
    end

    it 'raises ValidationError when signers are not an Array of Hashes' do
      expect do
        client.upload_and_request_signatures(
          source: pdf_source, signers: ['signer-id']
        )
      end.to raise_error(Assinafy::ValidationError)
    end

    it 'preflights every signer payload before uploading' do
      invalid_signers = signers + [{ full_name: 'Invalid Signer', email: 'not-an-email' }]

      expect do
        client.upload_and_request_signatures(source: pdf_source, signers: invalid_signers)
      end.to raise_error(Assinafy::ValidationError, /email/i)

      expect(a_request(:post, "#{base_url}/accounts/acc/documents")).not_to have_been_made
      expect(a_request(:post, "#{base_url}/accounts/acc/signers")).not_to have_been_made
    end

    it 'rejects malformed signer scalar fields before creating any remote resource' do
      malformed_signers = [{ full_name: 'Valid Signer' }, { full_name: 123, email: false }]

      expect do
        client.upload_and_request_signatures(source: pdf_source, signers: malformed_signers)
      end.to raise_error(Assinafy::ValidationError)

      expect(a_request(:post, "#{base_url}/accounts/acc/documents")).not_to have_been_made
      expect(a_request(:post, "#{base_url}/accounts/acc/signers")).not_to have_been_made
    end

    it 'validates wait_for_ready before uploading' do
      expect do
        client.upload_and_request_signatures(source: pdf_source, signers: signers, wait_for_ready: nil)
      end.to raise_error(Assinafy::ValidationError, /wait_for_ready/)

      expect(a_request(:post, "#{base_url}/accounts/acc/documents")).not_to have_been_made
    end

    it 'rejects an invalid account override before uploading' do
      expect do
        client.upload_and_request_signatures(
          source: pdf_source, signers: signers, account_id: false
        )
      end.to raise_error(Assinafy::ValidationError)
      expect(a_request(:post, %r{/documents})).not_to have_been_made
    end

    it 'does not fetch document details when wait_for_ready is false' do
      stub_upload
      ready = stub_ready
      stub_signers
      stub_assignment

      client.upload_and_request_signatures(
        source: pdf_source, signers: signers, wait_for_ready: false
      )

      expect(ready).not_to have_been_requested
    end

    it 'preserves API error context plus the document and previously created signer IDs' do
      workflow_signers = [
        { full_name: 'First Signer', email: 'first@example.test' },
        { full_name: 'Second Signer', email: 'second@example.test' }
      ]
      failure = { 'status' => 422, 'message' => 'Signer rejected' }
      stub_upload
      stub_ready
      stub_request(:post, "#{base_url}/accounts/acc/signers")
        .with(body: hash_including('email' => 'first@example.test'))
        .to_return(api_envelope({ 'id' => 'signer-1' }))
      stub_request(:post, "#{base_url}/accounts/acc/signers")
        .with(body: hash_including('email' => 'second@example.test'))
        .to_return(json_response(failure, status: 422))

      expect do
        client.upload_and_request_signatures(source: pdf_source, signers: workflow_signers)
      end.to raise_error(Assinafy::ApiError) { |error|
        expect(error.context).to include(status_code: 422, response_data: failure, signer_ids: ['signer-1'])
        expect(error.context[:document]).to include('id' => 'doc-1', 'status' => 'metadata_ready')
      }
      expect(a_request(:post, "#{base_url}/documents/doc-1/assignments")).not_to have_been_made
    end

    it 'raises a protocol Error with response and recovery context when a created signer has no ID' do
      malformed_signer = { 'full_name' => 'Example Signer' }
      stub_upload
      stub_ready
      stub_request(:post, "#{base_url}/accounts/acc/signers").to_return(api_envelope(malformed_signer))

      expect do
        client.upload_and_request_signatures(source: pdf_source, signers: signers)
      end.to raise_error(Assinafy::Error, /returned no usable ID/) { |error|
        expect(error).not_to be_a(Assinafy::ApiError)
        expect(error.context).to include(response_data: malformed_signer, signer_ids: [])
        expect(error.context[:document]).to include('id' => 'doc-1')
      }
    end

    it 'preserves the latest document from a readiness failure' do
      uploaded = { 'id' => 'doc-1', 'status' => 'uploaded' }
      failed = { 'id' => 'doc-1', 'status' => 'metadata_error' }
      stub_upload
      allow(client.documents).to receive(:wait_until_ready).and_raise(
        Assinafy::Error.new('processing failed', document: failed)
      )

      expect do
        client.upload_and_request_signatures(source: pdf_source, signers: signers)
      end.to raise_error(Assinafy::Error) { |error|
        expect(error.context).to include(document: failed, signer_ids: [])
        expect(error.context[:document]).not_to eq(uploaded)
      }
    end

    it 'raises a protocol Error with recovery context when an assignment has no usable ID' do
      stub_upload
      stub_ready
      stub_signers
      stub_request(:post, "#{base_url}/documents/doc-1/assignments")
        .to_return(api_envelope({ 'id' => 'not/a/path-segment' }))

      expect do
        client.upload_and_request_signatures(source: pdf_source, signers: signers)
      end.to raise_error(Assinafy::Error, /Assignment created.*no usable ID/) { |error|
        expect(error.context).to include(
          response_data: { 'id' => 'not/a/path-segment' },
          signer_ids:    ['signer-1']
        )
        expect(error.context[:document]).to include('id' => 'doc-1')
      }
    end
  end
end
