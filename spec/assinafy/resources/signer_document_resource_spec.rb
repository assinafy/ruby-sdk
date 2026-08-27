# frozen_string_literal: true

RSpec.describe Assinafy::Resources::SignerDocumentResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }
  let(:resource)   { described_class.new(connection) }

  def without_workspace_auth?(request)
    !request.headers.key?('X-Api-Key') && !request.headers.key?('Authorization')
  end

  describe '#search' do
    it 'GETs the signer documents/search endpoint with the documented search param' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents/search")
        .with(
          query:   hash_including('search' => 'audit'),
          headers: { 'X-Api-Key' => 'test-key' }
        )
        .to_return(api_envelope([{ 'id' => 'doc-1', 'status' => 'pending_signature' }]))

      result = resource.search('signer-1', 'audit')
      expect(result[:data].first['id']).to eq('doc-1')
    end

    it 'passes the signer-access-code as a query param when given' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents/search")
        .with(query: hash_including('signer-access-code' => 'code')) do |request|
          without_workspace_auth?(request)
        end
        .to_return(api_envelope([]))

      resource.search('signer-1', 'audit', {}, signer_access_code: 'code')
      expect(
        a_request(:get, "#{base_url}/signers/signer-1/documents/search")
          .with(query: hash_including('signer-access-code' => 'code'))
      ).to have_been_made
    end

    it 'rejects blank access codes and non-Hash params before making a request' do
      expect do
        resource.search('signer-1', 'audit', {}, signer_access_code: ' ')
      end.to raise_error(Assinafy::ValidationError, /Signer access code/)
      expect { resource.search('signer-1', 'audit', []) }
        .to raise_error(Assinafy::ValidationError, /query parameters/)
      expect(a_request(:get, "#{base_url}/signers/signer-1/documents/search")).not_to have_been_made
    end

    it 'isolates an access code supplied through legacy params from workspace credentials' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents/search")
        .with(query: hash_including('signer-access-code' => 'legacy-code')) do |request|
          without_workspace_auth?(request)
        end
        .to_return(api_envelope([]))

      resource.search('signer-1', 'contract', { signer_access_code: 'legacy-code' })

      expect(
        a_request(:get, "#{base_url}/signers/signer-1/documents/search")
          .with(query: hash_including('signer-access-code' => 'legacy-code'))
      ).to have_been_made
    end
  end

  describe '#current' do
    it 'calls the current signer document endpoint' do
      stub_request(:get, "#{base_url}/signers/signer-1/document")
        .with(query: hash_including('signer-access-code' => 'code')) do |request|
          without_workspace_auth?(request)
        end
        .to_return(api_envelope({ 'id' => 'doc-1' }))

      result = resource.current('signer-1', signer_access_code: 'code')

      expect(result['id']).to eq('doc-1')
    end

    it 'rejects nil and blank access codes before making a request' do
      [nil, '', ' '].each do |code|
        expect { resource.current('signer-1', signer_access_code: code) }
          .to raise_error(Assinafy::ValidationError, /Signer access code/)
      end
      expect(a_request(:get, "#{base_url}/signers/signer-1/document")).not_to have_been_made
    end
  end

  describe '#list' do
    it 'calls the signer documents endpoint with filters' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents")
        .with(query: hash_including('signer-access-code' => 'code', 'status' => 'pending_signature')) do |request|
          without_workspace_auth?(request)
        end
        .to_return(api_envelope([]))

      resource.list('signer-1', { status: 'pending_signature' }, signer_access_code: 'code')

      expect(
        a_request(:get, "#{base_url}/signers/signer-1/documents")
          .with(query: hash_including('signer-access-code' => 'code'))
      ).to have_been_made
    end

    it 'omits the access code from the query when authenticating via header' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents")
        .with(
          query:   hash_including('status' => 'pending_signature'),
          headers: { 'X-Api-Key' => 'test-key' }
        )
        .to_return(api_envelope([]))

      resource.list('signer-1', { status: 'pending_signature' })

      expect(
        a_request(:get, "#{base_url}/signers/signer-1/documents")
          .with(query: hash_excluding('signer-access-code'))
      ).to have_been_made
    end

    it 'rejects blank access codes and non-Hash params before making a request' do
      expect do
        resource.list('signer-1', {}, signer_access_code: '')
      end.to raise_error(Assinafy::ValidationError, /Signer access code/)
      expect { resource.list('signer-1', []) }
        .to raise_error(Assinafy::ValidationError, /query parameters/)
      expect(a_request(:get, "#{base_url}/signers/signer-1/documents")).not_to have_been_made
    end

    it 'isolates a hyphenated access-code param from workspace credentials' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents")
        .with(query: hash_including('signer-access-code' => 'legacy-code')) do |request|
          without_workspace_auth?(request)
        end
        .to_return(api_envelope([]))

      resource.list('signer-1', { 'signer-access-code' => 'legacy-code' })

      expect(
        a_request(:get, "#{base_url}/signers/signer-1/documents")
          .with(query: hash_including('signer-access-code' => 'legacy-code'))
      ).to have_been_made
    end
  end

  describe '#sign_multiple' do
    it 'requires at least one document ID' do
      expect do
        resource.sign_multiple([], signer_access_code: 'code')
      end.to raise_error(Assinafy::ValidationError)
    end

    it 'uses signer-only authentication and validates every document ID' do
      path = "#{base_url}/signers/documents/sign-multiple"
      stub_request(:put, path)
        .with(query: hash_including('signer-access-code' => 'code')) do |request|
          without_workspace_auth?(request)
        end
        .to_return(api_envelope([]))

      expect(resource.sign_multiple(%w[doc-1 doc-2], signer_access_code: 'code')).to eq([])
      expect { resource.sign_multiple(['doc-1', 2], signer_access_code: 'code') }
        .to raise_error(Assinafy::ValidationError, /Document ID/)
    end

    it 'rejects nil and blank access codes before making a request' do
      [nil, ' '].each do |code|
        expect { resource.sign_multiple(['doc-1'], signer_access_code: code) }
          .to raise_error(Assinafy::ValidationError, /Signer access code/)
      end
      expect(a_request(:put, "#{base_url}/signers/documents/sign-multiple")).not_to have_been_made
    end
  end

  describe '#decline_multiple' do
    it 'puts the document IDs and decline reason to the decline-multiple endpoint' do
      stub_request(:put, "#{base_url}/signers/documents/decline-multiple")
        .with(
          query: hash_including('signer-access-code' => 'code'),
          body:  hash_including('document_ids' => %w[doc-1 doc-2], 'decline_reason' => 'Unfavorable terms.')
        ) { |request| without_workspace_auth?(request) }
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

    it 'rejects a blank access code and mixed document-ID types without making a request' do
      expect do
        resource.decline_multiple(['doc-1'], decline_reason: 'No', signer_access_code: '')
      end.to raise_error(Assinafy::ValidationError, /Signer access code/)
      expect do
        resource.decline_multiple(['doc-1', 2], decline_reason: 'No', signer_access_code: 'code')
      end.to raise_error(Assinafy::ValidationError, /Document ID/)
      expect(a_request(:put, "#{base_url}/signers/documents/decline-multiple")).not_to have_been_made
    end

    it 'rejects a non-String or blank decline reason before making a request' do
      [nil, ' ', 123].each do |reason|
        expect do
          resource.decline_multiple(['doc-1'], decline_reason: reason, signer_access_code: 'code')
        end.to raise_error(Assinafy::ValidationError, /Decline reason/)
      end

      expect(a_request(:put, "#{base_url}/signers/documents/decline-multiple")).not_to have_been_made
    end
  end

  describe '#download' do
    it 'rejects unsupported artifact names' do
      expect { resource.download('signer-1', 'doc-1', '../users') }.to raise_error(Assinafy::ValidationError)
    end

    it 'calls the signer document download endpoint' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents/doc-1/download/original")
        .with do |request|
          without_workspace_auth?(request) && !request.uri.query.to_s.include?('signer-access-code')
        end
        .to_return(status: 200, body: 'PDF', headers: { 'Content-Type' => 'application/pdf' })

      expect(resource.download('signer-1', 'doc-1', 'original', signer_access_code: 'code')).to eq('PDF')
    end

    it 'works without a signer-access-code (public endpoint)' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents/doc-1/download/original")
        .with { |request| without_workspace_auth?(request) }
        .to_return(status: 200, body: 'PDF', headers: { 'Content-Type' => 'application/pdf' })

      # No signer_access_code passed -> the query param is omitted entirely.
      expect(resource.download('signer-1', 'doc-1', 'original')).to eq('PDF')
      expect(
        a_request(:get, "#{base_url}/signers/signer-1/documents/doc-1/download/original")
      ).to have_been_made
    end

    it 'rejects blank and non-String access codes before making a request' do
      [' ', 123].each do |code|
        expect do
          resource.download('signer-1', 'doc-1', 'original', signer_access_code: code)
        end.to raise_error(Assinafy::ValidationError, /Signer access code/)
      end
      expect(
        a_request(:get, "#{base_url}/signers/signer-1/documents/doc-1/download/original")
      ).not_to have_been_made
    end

    it 'gets the artifact path and returns the raw binary body' do
      stub_request(:get, "#{base_url}/signers/signer-1/documents/doc-1/download/certificated")
        .with do |request|
          without_workspace_auth?(request) && !request.uri.query.to_s.include?('signer-access-code')
        end
        .to_return(status: 200, body: 'PDFBYTES', headers: { 'Content-Type' => 'application/pdf' })

      result = resource.download('signer-1', 'doc-1', 'certificated', signer_access_code: 'code')

      expect(result).to eq('PDFBYTES')
      expect(
        a_request(:get, "#{base_url}/signers/signer-1/documents/doc-1/download/certificated")
          .with { |request| !request.uri.query.to_s.include?('signer-access-code') }
      ).to have_been_made
    end
  end
end
