# frozen_string_literal: true

RSpec.describe Assinafy::Resources::EnvelopeResource do
  let(:base_url) { 'https://api.assinafy.com.br/v1/accounts/acc/envelopes' }
  let(:resource) { described_class.new(build_test_connection, 'acc') }
  let(:envelope) { { 'id' => 'env', 'name' => 'Contract', 'message' => nil, 'documents' => [] } }
  let(:payload) do
    { name: 'Contract', signers: [{ id: 'signer' }], documents: [{ id: 'doc', signer_ids: ['signer'] }] }
  end

  it 'creates with a per-request idempotency header and preserves a zero credit ceiling' do
    request = stub_request(:post, base_url)
              .with(body:    payload.merge(max_total_credits: 0).to_json,
                    headers: { 'X-Api-Key' => 'test-key', 'Idempotency-Key' => 'once' })
              .to_return(api_envelope(envelope))
    expect(resource.create(payload.merge(max_total_credits: 0), idempotency_key: 'once')).to eq(envelope)
    expect(request).to have_been_requested.once
    expect(resource.instance_variable_get(:@connection).headers).not_to have_key('Idempotency-Key')
  end

  it 'estimates the same payload without creating an envelope' do
    cost = { 'total_credits' => 1.5, 'has_sufficient_resources' => true }
    stub_request(:post, "#{base_url}/estimate-cost").with(body: payload.to_json).to_return(api_envelope(cost))
    expect(resource.estimate_cost(payload)).to eq(cost)
  end

  it 'lists paginated envelopes with the workspace override and filters' do
    stub_request(:get, base_url.sub('/acc/', '/override/'))
      .with(query: { status: 'open', 'per-page' => 10 })
      .to_return(json_response({ status: 200, data: [envelope] }, headers: { 'X-Pagination-Total-Count' => '3' }))
    expect(resource.list({ status: 'open', per_page: 10 }, 'override')).to eq(data: [envelope], meta: { total: 3 })
  end

  it 'gets an envelope and preserves explicit null when updating the message' do
    stub_request(:get, "#{base_url}/env").to_return(api_envelope(envelope))
    stub_request(:patch, "#{base_url}/env").with(body: '{"message":null}').to_return(api_envelope(envelope))
    expect(resource.get('env')).to eq(envelope)
    expect(resource.update('env', message: nil)).to eq(envelope)
  end

  it 'returns cancellation results and deletes an envelope without deleting its documents' do
    result = [{ 'id' => 'doc', 'status' => 'rejected_by_user', 'cancelled' => true }]
    stub_request(:put, "#{base_url}/env/cancel").to_return(api_envelope(result))
    stub_request(:delete, "#{base_url}/env").to_return(api_envelope([]))
    expect(resource.cancel('env')).to eq(result)
    expect(resource.delete('env')).to be_nil
  end

  it 'exposes a closed-document refusal without hiding its code' do
    stub_request(:delete, "#{base_url}/env/documents/doc")
      .to_return(json_response({ status: 409, message: 'Document is closed', code: 'DocumentClosed' }, status: 409))
    expect { resource.remove_document('env', 'doc') }.to raise_error(Assinafy::ApiError) do |error|
      expect(error.error_code).to eq('DocumentClosed')
    end
  end

  it 'adds and removes a document and resends an envelope invitation' do
    document = { id: 'doc', signer_ids: ['signer'] }
    stub_request(:post, "#{base_url}/env/documents").with(body: document.to_json).to_return(api_envelope(envelope))
    stub_request(:delete, "#{base_url}/env/documents/doc").to_return(api_envelope(envelope))
    stub_request(:put, "#{base_url}/env/signers/signer/resend").to_return(api_envelope({ is_sent: true }))
    expect(resource.add_document('env', document)).to eq(envelope)
    expect(resource.remove_document('env', 'doc')).to eq(envelope)
    expect(resource.resend_notification('env', 'signer')).to eq('is_sent' => true)
  end

  it 'reads paginated activities and binary archive bytes' do
    stub_request(:get, "#{base_url}/env/activities").with(query: { sort: 'id', page: 2 })
                                                    .to_return(api_envelope([{ document_id: 'doc' }]))
    stub_request(:get, "#{base_url}/env/download/original")
      .to_return(status: 200, body: "PK\x00\xFF".b, headers: { 'Content-Type' => 'application/zip' })
    expect(resource.activities('env', sort: 'id', page: 2)).to eq(data: [{ 'document_id' => 'doc' }])
    expect(resource.download('env', 'original')).to eq("PK\x00\xFF".b)
  end

  it 'rejects invalid IDs, filters, patches and header values before the network' do
    aggregate_failures do
      expect { resource.get('../escape') }.to raise_error(Assinafy::ValidationError)
      expect { resource.list(status: 'bad') }.to raise_error(Assinafy::ValidationError)
      expect { resource.list(search: false) }.to raise_error(Assinafy::ValidationError)
      expect { resource.update('env', {}) }.to raise_error(Assinafy::ValidationError)
      expect { resource.update('env', message: false) }.to raise_error(Assinafy::ValidationError)
      expect { resource.update('env', document_ids: %w[doc doc]) }.to raise_error(Assinafy::ValidationError)
      expect { resource.create(payload, idempotency_key: "key\r\nInjected: value") }
        .to raise_error(Assinafy::ValidationError)
      expect { resource.download('env', '../original') }.to raise_error(Assinafy::ValidationError)
    end
  end

  it 'rejects invalid creation shapes before any charge' do
    [{ name: '' }, { name: '<bad>' }, { message: false }, { signers: [] }, { documents: [] },
     { signers: [{ id: 'signer', step: 1 }] }, { max_total_credits: -1 },
     { documents: [{ id: 'doc', signer_ids: ['other'] }] }].each do |invalid|
      expect { resource.create(payload.merge(invalid)) }.to raise_error(Assinafy::ValidationError)
    end
  end

  it 'accepts a document credit ceiling only when adding to an existing envelope' do
    document = { id: 'doc', signer_ids: ['signer'], max_total_credits: 0 }
    expect { resource.create(payload.merge(documents: [document])) }.to raise_error(Assinafy::ValidationError)
    stub_request(:post, "#{base_url}/env/documents").with(body: document.to_json).to_return(api_envelope(envelope))
    expect(resource.add_document('env', document)).to eq(envelope)
  end

  it 'rejects duplicate or unused signers and duplicate or oversized document lists' do
    aggregate_failures do
      expect { resource.create(payload.merge(signers: [{ id: 'signer' }, { id: 'unused' }])) }
        .to raise_error(Assinafy::ValidationError)
      expect { resource.create(payload.merge(signers: [{ id: 'signer' }, { id: 'signer' }])) }
        .to raise_error(Assinafy::ValidationError)
      expect { resource.create(payload.merge(documents: payload[:documents] * 2)) }
        .to raise_error(Assinafy::ValidationError)
      expect { resource.create(payload.merge(documents: payload[:documents] * 21)) }
        .to raise_error(Assinafy::ValidationError)
    end
  end

  it 'allows certificate signers on separate virtual documents but rejects sharing a document' do
    signers = [{ id: 'certificate', verification_method: 'DigitalCertificate' }, { id: 'signer' }]
    documents = [{ id: 'certificate-doc', signer_ids: ['certificate'] }, { id: 'doc', signer_ids: ['signer'] }]
    body = payload.merge(signers: signers, documents: documents)
    stub_request(:post, base_url).with(body: body.to_json).to_return(api_envelope(envelope))
    expect(resource.create(body)).to eq(envelope)
    documents[0][:signer_ids] << 'signer'
    expect { resource.create(body) }.to raise_error(Assinafy::ValidationError, /alone/)
  end

  it 'validates positioned collect fields against the document signer list' do
    settings = { left: 10, top: 10, width: 100, height: 40, fontSize: 12 }
    document = { id: 'doc', method: 'collect', signer_ids: ['signer'],
                 entries: [{ page_id: 'page', fields: [{ signer_id: 'other', field_id: 'field',
                                                       display_settings: settings }] }] }
    expect { resource.add_document('env', document) }.to raise_error(Assinafy::ValidationError)
    document[:entries][0][:fields][0][:signer_id] = 'signer'
    stub_request(:post, "#{base_url}/env/documents").with(body: document.to_json).to_return(api_envelope(envelope))
    expect(resource.add_document('env', document)).to eq(envelope)
  end
end
