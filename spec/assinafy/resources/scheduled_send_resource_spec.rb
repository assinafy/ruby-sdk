# frozen_string_literal: true

RSpec.describe Assinafy::Resources::ScheduledSendResource do
  let(:resource) { described_class.new(build_test_connection, 'acc') }
  let(:base_url) { 'https://api.assinafy.com.br/v1/accounts/acc/scheduled-sends' }

  it 'is exposed by the client' do
    expect(Assinafy::Client.new.scheduled_sends).to be_a(described_class)
  end

  it 'lists all send states with document filtering, pagination and an account override' do
    stub_request(:get, base_url.sub('/acc/', '/override/'))
      .with(query:   { 'document_id' => 'doc', 'per-page' => 10, 'page' => 2 },
            headers: { 'X-Api-Key' => 'test-key' })
      .to_return(json_response({ data: [{ id: 'send', status: 'failed', failure_reason: 'No balance' }] },
                               headers: { 'X-Pagination-Total-Count' => '12' }))
    expect(resource.list({ document_id: 'doc', per_page: 10, page: 2 }, 'override'))
      .to eq(data: [{ 'id' => 'send', 'status' => 'failed', 'failure_reason' => 'No balance' }], meta: { total: 12 })
  end

  it 'cancels pending sends and sends now with no request body' do
    { cancel: 'cancelled', send_now: 'sent' }.each do |method, status|
      route = method == :cancel ? 'cancel' : 'send'
      stub_request(:put, "#{base_url}/send-id/#{route}")
        .with(body: nil, headers: { 'X-Api-Key' => 'test-key' }).to_return(api_envelope({ status: status }))
      expect(resource.public_send(method, 'send-id')).to eq('status' => status)
    end
  end

  it 'does not retry a refused send or discard its credit ceiling refusal' do
    request = stub_request(:put, "#{base_url}/send-id/send")
              .to_return(json_response({ code: 'CreditCeilingExceeded', total_credits: 2 }, status: 409))
    expect { resource.send_now('send-id') }.to raise_error(Assinafy::ApiError) do |error|
      expect(error.error_code).to eq('CreditCeilingExceeded')
      expect(error.response_data['total_credits']).to eq(2)
    end
    expect(request).to have_been_requested.once
  end

  it 'validates IDs and filter shape before the network' do
    expect { resource.list(document_id: '../doc') }.to raise_error(Assinafy::ValidationError)
    expect { resource.list([]) }.to raise_error(Assinafy::ValidationError)
    expect { resource.cancel('../send') }.to raise_error(Assinafy::ValidationError)
    expect { resource.send_now('send', '../acc') }.to raise_error(Assinafy::ValidationError)
  end

  describe '.require_send_at' do
    let(:now) { Time.utc(2026, 11, 24, 12) }

    before { allow(Time).to receive(:now).and_return(now) }

    it 'accepts both boundaries, Unix seconds and ISO dates with UTC assumed without an offset' do
      expect(described_class.require_send_at((now + 3600).to_i)).to eq(now + 3600)
      expect(described_class.require_send_at((now + (90 * 86_400)).iso8601)).to eq(now + (90 * 86_400))
      expect(described_class.require_send_at('2026-11-24T13:00:00')).to eq(now + 3600)
      expect(described_class.require_send_at('2026-11-24T10:00:00-03:00')).to eq(now + 3600)
    end

    it 'rejects invalid dates and schedules outside the window' do
      [nil, true, {}, 1.5, 'tomorrow', '2026-02-30T12:00:00Z', '2026-11-25T12:00:00+99:99',
       (now + 3599).to_i, (now + (90 * 86_400) + 1).to_i].each do |value|
        expect { described_class.require_send_at(value) }.to raise_error(Assinafy::ValidationError)
      end
    end
  end

  it 'preserves fractional deadlines at the two-hour boundary and assumes UTC without an offset' do
    send_time = Time.iso8601('2026-11-24T12:00:00.5Z')
    expect(described_class.scheduled_expiration('2026-11-24T14:00:00.5Z', send_time))
      .to eq('2026-11-24T14:00:00.5Z')
    expect(described_class.scheduled_expiration('2026-11-24T14:00:00.5', send_time))
      .to eq('2026-11-24T14:00:00.5Z')
    expect { described_class.scheduled_expiration('2026-11-24T14:00:00.4Z', send_time) }
      .to raise_error(Assinafy::ValidationError)
  end
end
