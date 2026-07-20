# frozen_string_literal: true

RSpec.describe Assinafy::Resources::SignerDocumentResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }
  let(:resource)   { described_class.new(connection) }

  describe '#search' do
    it 'GETs the signer documents/search endpoint with a query param' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents/search")
        .with(query: hash_including('query' => 'audit'))
        .to_return(api_envelope([{ 'id' => 'doc-1', 'status' => 'pending_signature' }]))

      result = resource.search('signer-1', 'audit')
      expect(result[:data].first['id']).to eq('doc-1')
    end

    it 'passes the signer-access-code as a query param when given' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents/search")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(api_envelope([]))

      resource.search('signer-1', 'audit', {}, signer_access_code: 'code')
      expect(
        a_request(:get, "#{base_url}/signers/signer-1/documents/search")
          .with(query: hash_including('signer-access-code' => 'code'))
      ).to have_been_made
    end
  end

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

    it 'omits the access code from the query when authenticating via header' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents")
        .with(query: hash_including('status' => 'pending_signature'))
        .to_return(api_envelope([]))

      resource.list('signer-1', { status: 'pending_signature' })

      expect(
        a_request(:get, "#{base_url}/signers/signer-1/documents")
          .with(query: hash_excluding('signer-access-code'))
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

  describe '#decline_multiple' do
    it 'puts the document IDs and decline reason to the decline-multiple endpoint' do
      stub_request(:put, "#{base_url}/signers/documents/decline-multiple")
        .with(
          query: hash_including('signer-access-code' => 'code'),
          body:  hash_including('document_ids' => %w[doc-1 doc-2], 'decline_reason' => 'Unfavorable terms.')
        )
        .to_return(api_envelope([]))

      resource.decline_multiple(%w[doc-1 doc-2], decline_reason: 'Unfavorable terms.', signer_access_code: 'code')

      expect(
        a_request(:put, "#{base_url}/signers/documents/decline-multiple")
          .with(
            query: hash_including('signer-access-code' => 'code'),
            body:  hash_including('document_ids' => %w[doc-1 doc-2], 'decline_reason' => 'Unfavorable terms.')
          )
      ).to have_been_made
    end
  end

  describe '#download' do
    it 'calls the signer document download endpoint' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents/doc-1/download/original")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(status: 200, body: 'PDF', headers: { 'Content-Type' => 'application/pdf' })

      expect(resource.download('signer-1', 'doc-1', 'original', signer_access_code: 'code')).to eq('PDF')
    end

    it 'works without a signer-access-code (public endpoint)' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents/doc-1/download/original")
        .to_return(status: 200, body: 'PDF', headers: { 'Content-Type' => 'application/pdf' })

      # No signer_access_code passed -> the query param is omitted entirely.
      expect(resource.download('signer-1', 'doc-1', 'original')).to eq('PDF')
      expect(
        a_request(:get, "#{base_url}/signers/signer-1/documents/doc-1/download/original")
      ).to have_been_made
    end

    it 'gets the artifact path and returns the raw binary body' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents/doc-1/download/certificated")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(status: 200, body: 'PDFBYTES', headers: { 'Content-Type' => 'application/pdf' })

      result = resource.download('signer-1', 'doc-1', 'certificated', signer_access_code: 'code')

      expect(result).to eq('PDFBYTES')
      expect(
        a_request(:get, "#{base_url}/signers/signer-1/documents/doc-1/download/certificated")
          .with(query: hash_including('signer-access-code' => 'code'))
      ).to have_been_made
    end
  end
end
