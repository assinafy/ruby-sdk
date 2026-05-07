# frozen_string_literal: true

RSpec.describe Assinafy::Resources::DocumentResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }
  let(:resource)   { described_class.new(connection, 'acc') }

  describe '#details' do
    it 'raises when document ID is empty' do
      expect { resource.details('') }.to raise_error(Assinafy::ValidationError)
    end

    it 'fetches document details by ID' do
      stub_request(:get, "#{base_url}/documents/doc-1")
        .to_return(api_envelope({ 'id' => 'doc-1', 'status' => 'metadata_ready' }))

      result = resource.details('doc-1')
      expect(result['id']).to eq('doc-1')
    end
  end

  describe '#get' do
    it 'is an alias for details' do
      stub_request(:get, "#{base_url}/documents/doc-1")
        .to_return(api_envelope({ 'id' => 'doc-1' }))

      expect(resource.get('doc-1')['id']).to eq('doc-1')
    end
  end

  describe '#list' do
    it 'calls the list endpoint for the account' do
      stub_request(:get, "#{base_url}/accounts/acc/documents").to_return(api_envelope([]))

      result = resource.list
      expect(result[:data]).to eq([])
    end
  end

  describe '#statuses' do
    it 'calls the documented statuses endpoint' do
      stub_request(:get, "#{base_url}/documents/statuses")
        .to_return(api_envelope([{ 'code' => 'uploaded' }]))

      expect(resource.statuses.first['code']).to eq('uploaded')
    end
  end

  describe '#fully_signed?' do
    it 'returns true when document status is certificated' do
      stub_request(:get, "#{base_url}/documents/doc-1")
        .to_return(api_envelope({ 'id' => 'doc-1', 'status' => 'certificated' }))

      expect(resource.fully_signed?('doc-1')).to be true
    end

    it 'returns false when status is not certificated and summary is absent' do
      stub_request(:get, "#{base_url}/documents/doc-1")
        .to_return(api_envelope({ 'id' => 'doc-1', 'status' => 'pending_signature' }))

      expect(resource.fully_signed?('doc-1')).to be false
    end
  end

  describe '#signing_progress' do
    it 'calculates progress from assignment summary' do
      stub_request(:get, "#{base_url}/documents/doc-1")
        .to_return(api_envelope({
          'id'         => 'doc-1',
          'status'     => 'pending_signature',
          'assignment' => {
            'summary' => { 'signer_count' => 4, 'completed_count' => 2 }
          }
        }))

      result = resource.signing_progress('doc-1')
      expect(result[:total]).to      eq(4)
      expect(result[:signed]).to     eq(2)
      expect(result[:pending]).to    eq(2)
      expect(result[:percentage]).to eq(50.0)
    end
  end

  describe '#verify' do
    it 'raises when hash is empty' do
      expect { resource.verify('') }.to raise_error(Assinafy::ValidationError)
    end

    it 'calls the verify endpoint' do
      stub_request(:get, "#{base_url}/documents/abc123/verify")
        .to_return(api_envelope({ 'valid' => true }))

      result = resource.verify('abc123')
      expect(result['valid']).to be true
    end
  end

  describe '#delete' do
    it 'raises when document ID is empty' do
      expect { resource.delete('') }.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#download' do
    it 'rejects unsupported artifact names' do
      expect { resource.download('doc-1', 'unknown') }.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#upload' do
    it 'raises ValidationError when source is invalid' do
      expect { resource.upload(nil) }.to raise_error(Assinafy::ValidationError)
    end

    it 'raises ValidationError for non-PDF file extension' do
      expect do
        resource.upload(buffer: 'data', file_name: 'document.docx')
      end.to raise_error(Assinafy::ValidationError, /PDF/)
    end

    it 'raises ValidationError for empty buffer' do
      expect do
        resource.upload(buffer: '', file_name: 'document.pdf')
      end.to raise_error(Assinafy::ValidationError, /empty/)
    end
  end

  describe '#create_from_template' do
    it 'posts template document payload' do
      stub_request(:post, "#{base_url}/accounts/acc/templates/tmpl/documents")
        .to_return(api_envelope({ 'id' => 'doc-1' }))

      result = resource.create_from_template(
        'tmpl',
        [{ role_id: 'role', id: 'signer' }],
        { name: 'Contract' }
      )

      expect(result['id']).to eq('doc-1')
      expect(
        a_request(:post, "#{base_url}/accounts/acc/templates/tmpl/documents")
          .with(body: hash_including('name' => 'Contract'))
      ).to have_been_made
    end
  end

  describe '#public_info' do
    it 'calls the public document endpoint' do
      stub_request(:get, "#{base_url}/public/documents/doc-1")
        .to_return(api_envelope({ 'id' => 'doc-1' }))

      expect(resource.public_info('doc-1')['id']).to eq('doc-1')
    end
  end
end
