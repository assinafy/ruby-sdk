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

  describe '#self_data' do
    it 'uses signer-access-code as a query parameter' do
      stub_request(:get, "#{base_url}/signers/self")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(api_envelope({ 'id' => 'signer' }))

      result = resource.self_data(signer_access_code: 'code')
      expect(result['id']).to eq('signer')
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
            body: hash_including('has_accepted_terms' => true)
          )
      ).to have_been_made
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

    it 'returns the matching signer (case-insensitive comparison)' do
      stub_request(:get, "#{base_url}/accounts/test-account/signers")
        .with(query: hash_including('search' => 'john@example.com'))
        .to_return(api_envelope([{ 'id' => '1', 'full_name' => 'John', 'email' => 'JOHN@EXAMPLE.COM' }]))

      result = resource.find_by_email('john@example.com')
      expect(result['id']).to eq('1')
    end
  end
end
