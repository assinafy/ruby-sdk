# frozen_string_literal: true

RSpec.describe Assinafy::Resources::SignerResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }
  let(:resource)   { described_class.new(connection, 'test-account') }

  describe '#update' do
    it 'raises when signer ID is empty' do
      expect { resource.update('', { full_name: 'Test' }) }.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#delete' do
    it 'raises when signer ID is empty' do
      expect { resource.delete('') }.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#create' do
    it 'raises when no account ID is available' do
      r = described_class.new(connection)
      expect do
        r.create(full_name: 'Test', email: 'test@test.com')
      end.to raise_error(Assinafy::ValidationError)
    end

    it 'rejects an invalid email' do
      expect do
        resource.create(full_name: 'Test', email: 'not-an-email')
      end.to raise_error(Assinafy::ValidationError)
    end

    it 'uses custom account_id when provided' do
      stub_request(:post, "#{base_url}/accounts/custom-account/signers")
        .to_return(api_envelope({ 'id' => '123' }))

      resource.create({ full_name: 'Test', email: 'test@test.com' }, 'custom-account')

      expect(a_request(:post, "#{base_url}/accounts/custom-account/signers")).to have_been_made
    end

    it 'uses default account_id when custom not provided' do
      stub_request(:post, "#{base_url}/accounts/test-account/signers")
        .to_return(api_envelope({ 'id' => '123' }))

      resource.create(full_name: 'Test', email: 'test@test.com')

      expect(a_request(:post, "#{base_url}/accounts/test-account/signers")).to have_been_made
    end

    it 'maps phone to whatsapp_phone_number in the request body' do
      stub_request(:post, "#{base_url}/accounts/test-account/signers")
        .to_return(api_envelope({ 'id' => '123' }))

      resource.create(full_name: 'John', email: 'john@example.com', phone: '+5548999990000')

      expect(
        a_request(:post, "#{base_url}/accounts/test-account/signers")
          .with(body: hash_including(
            'full_name'             => 'John',
            'email'                 => 'john@example.com',
            'whatsapp_phone_number' => '+5548999990000'
          ))
      ).to have_been_made
    end
  end

  describe '#get' do
    it 'raises when signer ID is empty' do
      expect { resource.get('') }.to raise_error(Assinafy::ValidationError)
    end

    it 'fetches a signer by ID and returns the unwrapped data' do
      stub_request(:get, "#{base_url}/accounts/test-account/signers/sig-1")
        .to_return(api_envelope({ 'id' => 'sig-1', 'full_name' => 'John' }))

      result = resource.get('sig-1')

      expect(a_request(:get, "#{base_url}/accounts/test-account/signers/sig-1")).to have_been_made
      expect(result['id']).to eq('sig-1')
    end
  end

  describe '#self_data' do
    it 'uses signer-access-code as a query parameter' do
      stub_request(:get, "#{base_url}/signers/self")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(api_envelope({ 'id' => 'signer' }))

      result = resource.self_data(signer_access_code: 'code')

      expect(
        a_request(:get, "#{base_url}/signers/self")
          .with(query: hash_including('signer-access-code' => 'code'))
      ).to have_been_made
      expect(result['id']).to eq('signer')
    end
  end

  describe '#accept_terms' do
    it 'puts signer-access-code in the request body' do
      stub_request(:put, "#{base_url}/signers/accept-terms")
        .to_return(api_envelope({ 'has_accepted_terms' => true }))

      resource.accept_terms(signer_access_code: 'code')

      expect(
        a_request(:put, "#{base_url}/signers/accept-terms")
          .with(body: hash_including('signer-access-code' => 'code'))
      ).to have_been_made
    end
  end

  describe '#verify_email' do
    it 'posts hyphenated verification-code and signer-access-code in the body' do
      stub_request(:post, "#{base_url}/verify")
        .to_return(json_response({ 'message' => 'Code verified successfully' }))

      resource.verify_email(verification_code: '123456', signer_access_code: 'code')

      expect(
        a_request(:post, "#{base_url}/verify")
          .with(body: hash_including(
            'verification-code'  => '123456',
            'signer-access-code' => 'code'
          ))
      ).to have_been_made
    end
  end

  describe '#confirm_data' do
    it 'puts signer data with signer-access-code query parameter' do
      stub_request(:put, "#{base_url}/documents/doc/signers/confirm-data")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(api_envelope({}))

      resource.confirm_data('doc', { has_accepted_terms: true }, signer_access_code: 'code')

      expect(
        a_request(:put, "#{base_url}/documents/doc/signers/confirm-data")
          .with(
            query: hash_including('signer-access-code' => 'code'),
            body:  hash_including('has_accepted_terms' => true)
          )
      ).to have_been_made
    end
  end

  describe '#upload_signature' do
    it 'posts raw bytes with Content-Type and type + signer-access-code query params' do
      stub_request(:post, "#{base_url}/signature")
        .with(query: hash_including('signer-access-code' => 'code', 'type' => 'signature'))
        .to_return(api_envelope([]))

      result = resource.upload_signature('rawbytes', signer_access_code: 'code', content_type: 'image/png')

      expect(
        a_request(:post, "#{base_url}/signature")
          .with(
            query:   hash_including('signer-access-code' => 'code', 'type' => 'signature'),
            body:    'rawbytes',
            headers: { 'Content-Type' => 'image/png' }
          )
      ).to have_been_made
      expect(result).to eq([])
    end
  end

  describe '#download_signature' do
    it 'gets the typed signature path and returns the raw binary bytes' do
      stub_request(:get, "#{base_url}/signature/initial")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(status: 200, body: 'PNGBYTES', headers: { 'Content-Type' => 'image/png' })

      result = resource.download_signature(signer_access_code: 'code', type: 'initial')

      expect(
        a_request(:get, "#{base_url}/signature/initial")
          .with(query: hash_including('signer-access-code' => 'code'))
      ).to have_been_made
      expect(result).to eq('PNGBYTES')
      expect(result.encoding).to eq(Encoding::ASCII_8BIT)
    end
  end

  describe '#list' do
    it 'passes search via query params' do
      stub_request(:get, "#{base_url}/accounts/test-account/signers")
        .with(query: hash_including('search' => 'john@example.com'))
        .to_return(api_envelope([]))

      resource.list(search: 'john@example.com')

      expect(
        a_request(:get, "#{base_url}/accounts/test-account/signers")
          .with(query: hash_including('search' => 'john@example.com'))
      ).to have_been_made
    end

    it 'returns meta parsed from X-Pagination-* response headers' do
      stub_request(:get, "#{base_url}/accounts/test-account/signers")
        .with(query: hash_including('page' => '2'))
        .to_return(
          api_envelope([]).merge(
            headers: {
              'Content-Type'              => 'application/json',
              'x-pagination-current-page' => '2',
              'x-pagination-per-page'     => '20',
              'x-pagination-total-count'  => '45',
              'x-pagination-page-count'   => '3'
            }
          )
        )

      result = resource.list(page: 2)

      expect(result[:meta]).to eq(
        { current_page: 2, per_page: 20, total: 45, last_page: 3 }
      )
    end
  end

  describe '#find_by_email' do
    it 'returns nil when no signer matches' do
      stub_request(:get, "#{base_url}/accounts/test-account/signers")
        .with(query: hash_including('search' => 'nobody@example.com'))
        .to_return(api_envelope([]))

      expect(resource.find_by_email('nobody@example.com')).to be_nil
    end

    it 'requests per-page 50 and returns the matching signer (case-insensitive)' do
      stub_request(:get, "#{base_url}/accounts/test-account/signers")
        .with(query: hash_including('search' => 'john@example.com', 'per-page' => '50'))
        .to_return(api_envelope([{ 'id' => '1', 'full_name' => 'John', 'email' => 'JOHN@EXAMPLE.COM' }]))

      result = resource.find_by_email('john@example.com')

      expect(
        a_request(:get, "#{base_url}/accounts/test-account/signers")
          .with(query: hash_including('search' => 'john@example.com', 'per-page' => '50'))
      ).to have_been_made
      expect(result['id']).to eq('1')
    end
  end
end
