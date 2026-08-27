# frozen_string_literal: true

RSpec.describe Assinafy::Resources::DocumentResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }
  let(:resource)   { described_class.new(connection, 'acc') }

  def without_workspace_auth?(request)
    !request.headers.key?('X-Api-Key') && !request.headers.key?('Authorization')
  end

  describe '#search' do
    it 'GETs the account documents/search endpoint with the documented search param' do
      stub_request(:get, "#{base_url}/accounts/acc/documents/search")
        .with(query: hash_including('search' => 'contract'))
        .to_return(api_envelope([{ 'id' => 'doc-1', 'name' => 'contract.pdf' }]))

      result = resource.search('contract')
      expect(result[:data].first['id']).to eq('doc-1')
    end

    it 'rejects non-Hash query parameters before making a request' do
      expect { resource.search('contract', []) }
        .to raise_error(Assinafy::ValidationError, /search parameters/)
      expect(a_request(:get, "#{base_url}/accounts/acc/documents/search")).not_to have_been_made
    end
  end

  describe '#rename' do
    it 'PATCHes /documents/{id} with the new name' do
      stub_request(:patch, "#{base_url}/documents/doc-1")
        .with(body: hash_including('name' => 'renamed.pdf'))
        .to_return(api_envelope({ 'id' => 'doc-1', 'name' => 'renamed.pdf' }))

      expect(resource.rename('doc-1', 'renamed.pdf')['name']).to eq('renamed.pdf')
    end

    it 'raises when the name is blank' do
      expect { resource.rename('doc-1', '') }.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#details' do
    it 'raises when document ID is empty' do
      expect { resource.details('') }.to raise_error(Assinafy::ValidationError)
    end

    it 'rejects IDs that can alter the request path' do
      expect { resource.details('../users') }.to raise_error(Assinafy::ValidationError)
      expect { resource.details('doc?admin=true') }.to raise_error(Assinafy::ValidationError)
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

    it 'rejects a malformed non-Array response' do
      stub_request(:get, "#{base_url}/documents/statuses")
        .to_return(api_envelope({ 'code' => 'uploaded' }))

      expect { resource.statuses }.to raise_error(Assinafy::Error, /Array data payload/)
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
        .with { |request| without_workspace_auth?(request) }
        .to_return(api_envelope({ 'is_valid' => true }))

      result = resource.verify('abc123')
      expect(result['is_valid']).to be true
    end
  end

  describe '#delete' do
    it 'raises when document ID is empty' do
      expect { resource.delete('') }.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#download' do
    it 'supports the documented pades artifact' do
      stub_request(:get, "#{base_url}/documents/doc-1/download/pades")
        .to_return(status: 200, body: 'PDF', headers: { 'Content-Type' => 'application/pdf' })

      expect(resource.download('doc-1', 'pades')).to eq('PDF')
    end

    it 'rejects unsupported artifact names' do
      expect { resource.download('doc-1', 'unknown') }.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#upload' do
    it 'rejects non-Hash options before making a request' do
      expect { resource.upload({ buffer: '%PDF-1.7', file_name: 'document.pdf' }, []) }
        .to raise_error(Assinafy::ValidationError, /Upload options/)
      expect(a_request(:post, "#{base_url}/accounts/acc/documents")).not_to have_been_made
    end

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

    it 'raises ValidationError when a file cannot be read' do
      expect { resource.upload('/path/that/does/not/exist.pdf') }
        .to raise_error(Assinafy::ValidationError, /Unable to read/)
    end

    it 'normalizes invalid file paths to ValidationError' do
      expect { resource.upload("bad\0path.pdf") }
        .to raise_error(Assinafy::ValidationError, /Unable to read/)
    end

    it 'bounds file reads before enforcing the maximum upload size' do
      max_bytes = described_class::MAX_UPLOAD_BYTES
      oversized = '%PDF-1.7'.dup
      allow(oversized).to receive(:bytesize).and_return(max_bytes + 1)
      allow(File).to receive(:binread).with('/tmp/oversized.pdf', max_bytes + 1).and_return(oversized)

      expect { resource.upload('/tmp/oversized.pdf') }
        .to raise_error(Assinafy::ValidationError, /25MB/)
    end

    it 'rejects a pdf extension with non-PDF content' do
      expect { resource.upload(buffer: 'plain text', file_name: 'document.pdf') }
        .to raise_error(Assinafy::ValidationError, /content is not a PDF/)
    end

    it 'reports a malformed success payload as an operational error with response context' do
      malformed_documents = [
        { 'name' => 'document.pdf' },
        { 'id' => '' },
        { 'id' => 123 },
        { 'id' => '../invalid' }
      ]

      malformed_documents.each do |document|
        stub_request(:post, "#{base_url}/accounts/acc/documents").to_return(api_envelope(document))

        expect { resource.upload(buffer: '%PDF-1.7', file_name: 'document.pdf') }
          .to raise_error do |error|
            expect(error.class).to eq(Assinafy::Error)
            expect(error.context[:document]).to eq(document)
          end
      end
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

    it 'rejects non-Hash signer entries before making a request' do
      expect { resource.create_from_template('tmpl', [{ role_id: 'role' }, 'bad']) }
        .to raise_error(Assinafy::ValidationError, /Signer/)
      expect(a_request(:post, "#{base_url}/accounts/acc/templates/tmpl/documents")).not_to have_been_made
    end
  end

  describe '#public_info' do
    it 'calls the public document endpoint' do
      stub_request(:get, "#{base_url}/public/documents/doc-1")
        .with { |request| without_workspace_auth?(request) }
        .to_return(api_envelope({ 'id' => 'doc-1' }))

      expect(resource.public_info('doc-1')['id']).to eq('doc-1')
    end
  end

  describe '#list_tags' do
    it 'calls the document tags endpoint' do
      stub_request(:get, "#{base_url}/accounts/acc/documents/doc-1/tags")
        .to_return(api_envelope([{ 'id' => 'tag-1', 'name' => 'Contracts' }]))

      expect(resource.list_tags('doc-1').first['id']).to eq('tag-1')
    end
  end

  describe '#replace_tags' do
    it 'allows an empty array to detach every tag' do
      stub_request(:put, "#{base_url}/accounts/acc/documents/doc-1/tags")
        .to_return(api_envelope([]))

      expect(resource.replace_tags('doc-1', [])).to eq([])
      expect(
        a_request(:put, "#{base_url}/accounts/acc/documents/doc-1/tags")
          .with(body: { 'tags' => [] })
      ).to have_been_made
    end
  end

  describe '#append_tags' do
    it 'posts tag IDs to the append endpoint' do
      stub_request(:post, "#{base_url}/accounts/acc/documents/doc-1/tags")
        .to_return(api_envelope([{ 'id' => 'tag-1', 'name' => 'Urgent' }]))

      result = resource.append_tags('doc-1', ['tag-1'])

      expect(result.first['name']).to eq('Urgent')
      expect(
        a_request(:post, "#{base_url}/accounts/acc/documents/doc-1/tags")
          .with(body: { 'tags' => ['tag-1'] })
      ).to have_been_made
    end

    it 'rejects empty tag names' do
      expect { resource.append_tags('doc-1', ['']) }.to raise_error(Assinafy::ValidationError)
    end

    it 'rejects non-String tags before making a request' do
      expect { resource.append_tags('doc-1', ['tag-1', 2]) }
        .to raise_error(Assinafy::ValidationError, /Strings/)
      expect(a_request(:post, "#{base_url}/accounts/acc/documents/doc-1/tags")).not_to have_been_made
    end
  end

  describe '#detach_tag' do
    it 'calls the detach endpoint' do
      stub_request(:delete, "#{base_url}/accounts/acc/documents/doc-1/tags/tag-1")
        .to_return(api_envelope({ 'detached' => true }))

      expect(resource.detach_tag('doc-1', 'tag-1')['detached']).to be true
    end
  end

  describe '#activities' do
    it 'fetches the document activity log' do
      stub_request(:get, "#{base_url}/documents/doc-1/activities")
        .to_return(api_envelope([{ 'id' => 8304, 'event' => 'document_uploaded' }]))

      result = resource.activities('doc-1')

      expect(result.first['event']).to eq('document_uploaded')
      expect(a_request(:get, "#{base_url}/documents/doc-1/activities")).to have_been_made
    end

    it 'rejects null instead of silently treating it as an empty list' do
      stub_request(:get, "#{base_url}/documents/doc-1/activities").to_return(api_envelope(nil))

      expect { resource.activities('doc-1') }.to raise_error(Assinafy::Error, /Array data payload/)
    end
  end

  describe '#thumbnail' do
    it 'downloads the thumbnail as raw bytes' do
      stub_request(:get, "#{base_url}/documents/doc-1/thumbnail")
        .to_return(status: 200, body: 'PNG', headers: { 'Content-Type' => 'image/png' })

      expect(resource.thumbnail('doc-1')).to eq('PNG')
      expect(a_request(:get, "#{base_url}/documents/doc-1/thumbnail")).to have_been_made
    end

    it 'raises ApiError for a successful HTTP response containing an error envelope' do
      stub_request(:get, "#{base_url}/documents/doc-1/thumbnail")
        .to_return(json_response({ 'status' => 404, 'message' => 'Not found' }))

      expect { resource.thumbnail('doc-1') }.to raise_error(Assinafy::ApiError)
    end
  end

  describe '#download_page' do
    it 'downloads a single page as raw bytes' do
      stub_request(:get, "#{base_url}/documents/doc-1/pages/page-1/download")
        .to_return(status: 200, body: 'PNG', headers: { 'Content-Type' => 'image/png' })

      expect(resource.download_page('doc-1', 'page-1')).to eq('PNG')
      expect(a_request(:get, "#{base_url}/documents/doc-1/pages/page-1/download")).to have_been_made
    end
  end

  describe '#estimate_cost_from_template' do
    it 'posts the signers payload to the estimate-cost endpoint' do
      path = "#{base_url}/accounts/acc/templates/tmpl/documents/estimate-cost"
      stub_request(:post, path).to_return(api_envelope({ 'total_credits' => 0 }))

      result = resource.estimate_cost_from_template('tmpl', [{ role_id: 'role' }])

      expect(result['total_credits']).to eq(0)
      expect(
        a_request(:post, path).with(body: hash_including('signers' => [{ 'role_id' => 'role' }]))
      ).to have_been_made
    end
  end

  describe '#send_token' do
    it 'supports the current OpenAPI request without a body' do
      path = "#{base_url}/public/documents/doc-1/send-token"
      stub_request(:put, path).with(body: nil) { |request| without_workspace_auth?(request) }
                              .to_return(json_response({ 'status' => 200, 'message' => 'Token sent' }))

      expect(resource.send_token('doc-1')).to be_nil
      expect(a_request(:put, path).with(body: nil)).to have_been_made
    end

    it 'supports the current OpenAPI email body' do
      path = "#{base_url}/public/documents/doc-1/send-token"
      stub_request(:put, path)
        .with(body: { 'email' => 'recipient@example.com' }) { |request| without_workspace_auth?(request) }
        .to_return(json_response({ 'status' => 200, 'message' => 'Token sent' }))

      expect(resource.send_token('doc-1', email: 'recipient@example.com')).to be_nil
      expect(a_request(:put, path).with(body: { 'email' => 'recipient@example.com' })).to have_been_made
    end

    it 'puts the recipient and channel to the send-token endpoint' do
      path = "#{base_url}/public/documents/doc-1/send-token"
      stub_request(:put, path)
        .with { |request| without_workspace_auth?(request) }
        .to_return(api_envelope({ 'channel' => 'email' }))

      result = resource.send_token('doc-1', recipient: 'recipient@example.com', channel: 'email')

      expect(result['channel']).to eq('email')
      expect(
        a_request(:put, path).with(body: { 'recipient' => 'recipient@example.com', 'channel' => 'email' })
      ).to have_been_made
    end

    it 'raises and makes no request when recipient is blank' do
      expect do
        resource.send_token('doc-1', recipient: '', channel: 'email')
      end.to raise_error(Assinafy::ValidationError)
      expect(a_request(:put, %r{/send-token})).not_to have_been_made
    end

    it 'raises and makes no request when channel is blank' do
      expect do
        resource.send_token('doc-1', recipient: 'recipient@example.com', channel: '')
      end.to raise_error(Assinafy::ValidationError)
      expect(a_request(:put, %r{/send-token})).not_to have_been_made
    end

    it 'rejects mixing the OpenAPI and deployed request shapes' do
      expect do
        resource.send_token('doc-1', email: 'recipient@example.com',
                                      recipient: 'recipient@example.com', channel: 'email')
      end.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#wait_until_ready' do
    it 'returns the document once details reports a ready status' do
      stub_request(:get, "#{base_url}/documents/doc-1")
        .to_return(api_envelope({ 'id' => 'doc-1', 'status' => 'metadata_ready' }))

      result = resource.wait_until_ready('doc-1', max_wait_seconds: 5, poll_interval_seconds: 1)

      expect(result['status']).to eq('metadata_ready')
      expect(a_request(:get, "#{base_url}/documents/doc-1")).to have_been_made
    end

    it 'propagates API errors instead of masking them as timeouts' do
      stub_request(:get, "#{base_url}/documents/doc-1")
        .to_return(json_response({ 'status' => 401, 'message' => 'Unauthorized' }, status: 401))

      expect do
        resource.wait_until_ready('doc-1', max_wait_seconds: 5, poll_interval_seconds: 1)
      end.to raise_error(Assinafy::ApiError) { |error| expect(error.status_code).to eq(401) }
    end

    it 'stops immediately when document processing reaches a failed state' do
      stub_request(:get, "#{base_url}/documents/doc-1")
        .to_return(api_envelope({ 'id' => 'doc-1', 'status' => 'failed' }))

      error = begin
        resource.wait_until_ready('doc-1', max_wait_seconds: 5, poll_interval_seconds: 1)
      rescue Assinafy::Error => e
        e
      end

      expect(error.class).to eq(Assinafy::Error)
      expect(error.message).to include('processing failed')
      expect(error.context[:document]).to include('id' => 'doc-1', 'status' => 'failed')
    end

    it 'rejects non-positive polling intervals' do
      expect do
        resource.wait_until_ready('doc-1', max_wait_seconds: 5, poll_interval_seconds: 0)
      end.to raise_error(Assinafy::ValidationError)
    end

    it 'does not issue another request after the polling deadline' do
      stub_request(:get, "#{base_url}/documents/doc-1")
        .to_return(api_envelope({ 'id' => 'doc-1', 'status' => 'metadata_processing' }))
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0, 0, 0, 1)
      allow(resource).to receive(:sleep)

      error = begin
        resource.wait_until_ready('doc-1', max_wait_seconds: 1, poll_interval_seconds: 1)
      rescue Assinafy::Error => e
        e
      end

      expect(error.class).to eq(Assinafy::Error)
      expect(error.message).to include('Timeout')
      expect(error.context).to include(document_id: 'doc-1', attempts: 1)
      expect(error.context[:document]).to include('status' => 'metadata_processing')
      expect(a_request(:get, "#{base_url}/documents/doc-1")).to have_been_made.once
    end
  end
end
