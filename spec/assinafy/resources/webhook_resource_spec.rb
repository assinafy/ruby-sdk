# frozen_string_literal: true

RSpec.describe Assinafy::Resources::WebhookResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }

  describe '#register' do
    it 'updates subscriptions with explicit events' do
      stub_request(:put, "#{base_url}/accounts/acc/webhooks/subscriptions")
        .to_return(api_envelope({ 'is_active' => true }))

      resource = described_class.new(connection, 'acc')
      resource.register(
        url:    'https://example.com/webhook',
        email:  'ops@example.com',
        events: %w[document_ready document_prepared]
      )

      expect(
        a_request(:put, "#{base_url}/accounts/acc/webhooks/subscriptions")
          .with(body: {
            'url'       => 'https://example.com/webhook',
            'email'     => 'ops@example.com',
            'events'    => %w[document_ready document_prepared],
            'is_active' => true
          })
      ).to have_been_made
    end

    it 'raises when URL is missing' do
      resource = described_class.new(connection, 'acc')
      expect { resource.register(email: 'ops@example.com') }.to raise_error(Assinafy::ValidationError)
    end

    it 'raises when email is missing' do
      resource = described_class.new(connection, 'acc')
      expect { resource.register(url: 'https://example.com') }.to raise_error(Assinafy::ValidationError)
    end

    it 'raises when events are missing' do
      resource = described_class.new(connection, 'acc')
      expect do
        resource.register(url: 'https://example.com', email: 'ops@example.com')
      end.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#update (alias)' do
    it 'dispatches to the same PUT subscriptions request as register' do
      stub_request(:put, "#{base_url}/accounts/acc/webhooks/subscriptions")
        .to_return(api_envelope({ 'is_active' => true }))

      resource = described_class.new(connection, 'acc')
      resource.update(
        url:    'https://example.com/webhook',
        email:  'ops@example.com',
        events: %w[document_ready]
      )

      expect(
        a_request(:put, "#{base_url}/accounts/acc/webhooks/subscriptions")
          .with(body: {
            'url'       => 'https://example.com/webhook',
            'email'     => 'ops@example.com',
            'events'    => %w[document_ready],
            'is_active' => true
          })
      ).to have_been_made
    end
  end

  describe '#get' do
    it 'GETs the subscription and returns the object when it exists' do
      stub_request(:get, "#{base_url}/accounts/acc/webhooks/subscriptions")
        .to_return(api_envelope({ 'url' => 'https://example.com/webhook', 'is_active' => true }))

      resource = described_class.new(connection, 'acc')
      result   = resource.get

      expect(a_request(:get, "#{base_url}/accounts/acc/webhooks/subscriptions")).to have_been_made
      expect(result['url']).to eq('https://example.com/webhook')
    end

    it 'returns nil on 404' do
      stub_request(:get, "#{base_url}/accounts/acc/webhooks/subscriptions")
        .to_return(api_envelope({ 'message' => 'Not found' }, status: 404))

      resource = described_class.new(connection, 'acc')

      expect(resource.get).to be_nil
      expect(a_request(:get, "#{base_url}/accounts/acc/webhooks/subscriptions")).to have_been_made
    end
  end

  describe '#list_event_types' do
    it 'calls the global /webhooks/event-types endpoint' do
      stub_request(:get, "#{base_url}/webhooks/event-types").to_return(api_envelope([]))

      resource = described_class.new(connection)
      resource.list_event_types

      expect(a_request(:get, "#{base_url}/webhooks/event-types")).to have_been_made
    end

    it 'returns the array of event-type entries' do
      catalogue = [{ 'id' => 'document_ready', 'description' => 'Document is ready' }]
      stub_request(:get, "#{base_url}/webhooks/event-types").to_return(api_envelope(catalogue))

      resource = described_class.new(connection)
      result   = resource.list_event_types

      expect(result).to eq([{ 'id' => 'document_ready', 'description' => 'Document is ready' }])
    end
  end

  describe '#list_dispatches' do
    it 'calls the correct account URL and parses pagination headers' do
      stub_request(:get, "#{base_url}/accounts/acc/webhooks")
        .with(query: hash_including('delivered' => 'false'))
        .to_return(
          api_envelope([]).merge(
            headers: {
              'Content-Type'              => 'application/json',
              'x-pagination-current-page' => '1',
              'x-pagination-per-page'     => '20',
              'x-pagination-total-count'  => '2',
              'x-pagination-page-count'   => '1'
            }
          )
        )

      resource = described_class.new(connection, 'acc')
      result   = resource.list_dispatches(delivered: false, 'per-page': 20)

      expect(a_request(:get, "#{base_url}/accounts/acc/webhooks")
        .with(query: hash_including('delivered' => 'false'))).to have_been_made
      expect(result[:meta]).to eq({ current_page: 1, per_page: 20, total: 2, last_page: 1 })
    end
  end

  describe '#retry_dispatch' do
    it 'raises ValidationError when dispatch_id is empty' do
      resource = described_class.new(connection, 'acc')
      expect { resource.retry_dispatch('') }.to raise_error(Assinafy::ValidationError)
    end

    it 'POSTs to /accounts/{id}/webhooks/{dispatch_id}/retry' do
      stub_request(:post, "#{base_url}/accounts/acc/webhooks/dsp-1/retry")
        .to_return(api_envelope({ 'id' => 'dsp-1', 'delivered' => true }))

      resource = described_class.new(connection, 'acc')
      resource.retry_dispatch('dsp-1')

      expect(a_request(:post, "#{base_url}/accounts/acc/webhooks/dsp-1/retry")).to have_been_made
    end
  end

  describe '#inactivate' do
    it 'PUT to /accounts/{id}/webhooks/inactivate' do
      stub_request(:put, "#{base_url}/accounts/acc/webhooks/inactivate")
        .to_return(api_envelope({ 'is_active' => false }))

      resource = described_class.new(connection, 'acc')
      resource.inactivate

      expect(a_request(:put, "#{base_url}/accounts/acc/webhooks/inactivate")).to have_been_made
    end
  end
end
