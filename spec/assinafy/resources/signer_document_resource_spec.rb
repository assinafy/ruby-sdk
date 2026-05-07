# frozen_string_literal: true

RSpec.describe Assinafy::Resources::SignerDocumentResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }
  let(:resource)   { described_class.new(connection) }

  describe '#current' do
    it 'calls the current signer document endpoint' do
      stub_request(:get, "#{base_url}/signers/signer-1/document")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(api_envelope({ 'id' => 'doc-1' }))

      result = resource.current('signer-1', signer_access_code: 'code')

      expect(result['id']).to eq('doc-1')
    end
  end

  describe '#list' do
    it 'calls the signer documents endpoint with filters' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents")
        .with(query: hash_including('signer-access-code' => 'code', 'status' => 'pending_signature'))
        .to_return(api_envelope([]))

      resource.list('signer-1', { status: 'pending_signature' }, signer_access_code: 'code')

      expect(
        a_request(:get, "#{base_url}/signers/signer-1/documents")
          .with(query: hash_including('signer-access-code' => 'code'))
      ).to have_been_made
    end
  end

  describe '#sign_multiple' do
    it 'requires at least one document ID' do
      expect do
        resource.sign_multiple([], signer_access_code: 'code')
      end.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#download' do
    it 'calls the signer document download endpoint' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents/doc-1/download/original")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(status: 200, body: 'PDF', headers: { 'Content-Type' => 'application/pdf' })

      expect(resource.download('signer-1', 'doc-1', 'original', signer_access_code: 'code')).to eq('PDF')
    end
  end
end
