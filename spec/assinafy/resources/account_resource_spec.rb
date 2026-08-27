# frozen_string_literal: true

RSpec.describe Assinafy::Resources::AccountResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }
  let(:resource)   { described_class.new(connection, 'acc') }

  describe '#list' do
    it 'GETs /accounts and returns { data:, meta: }' do
      stub_request(:get, "#{base_url}/accounts")
        .to_return(api_envelope([{ 'id' => 'acc', 'name' => 'MT', 'roles' => ['owner'] }]))

      result = resource.list
      expect(result[:data].first['id']).to eq('acc')
      expect(result[:meta]).to be_nil
    end
  end

  describe '#create' do
    it 'POSTs a name and returns the created account' do
      stub_request(:post, "#{base_url}/accounts")
        .with(body: hash_including('name' => 'Acme Inc.'))
        .to_return(api_envelope({ 'id' => 'new', 'name' => 'Acme Inc.' }))

      result = resource.create(name: 'Acme Inc.')
      expect(result['id']).to eq('new')
    end

    it 'raises when name is blank' do
      expect { resource.create(notification_sender_type: 'User') }.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#get' do
    it 'GETs /accounts/{id} using the default account' do
      stub_request(:get, "#{base_url}/accounts/acc")
        .to_return(api_envelope({ 'id' => 'acc', 'name' => 'MT' }))

      expect(resource.get['id']).to eq('acc')
    end

    it 'rejects a blank account ID' do
      expect { described_class.new(connection, '').get }.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#update' do
    it 'PUTs the account payload' do
      stub_request(:put, "#{base_url}/accounts/acc")
        .with(body: hash_including('name' => 'Renamed'))
        .to_return(api_envelope({ 'id' => 'acc', 'name' => 'Renamed' }))

      expect(resource.update(name: 'Renamed')['name']).to eq('Renamed')
    end
  end

  describe '#delete' do
    it 'rejects non-boolean force values' do
      expect { resource.delete(force: 'false') }.to raise_error(Assinafy::ValidationError)
    end

    it 'rejects an explicit invalid account override instead of using the default' do
      expect { resource.delete(account_id_override: false) }.to raise_error(Assinafy::ValidationError)
      expect(a_request(:delete, %r{/accounts/})).not_to have_been_made
    end

    it 'DELETEs with a force flag in the body and returns nil' do
      stub_request(:delete, "#{base_url}/accounts/xyz")
        .with(body: hash_including('force' => true))
        .to_return(api_envelope([]))

      expect(resource.delete(force: true, account_id_override: 'xyz')).to be_nil
      expect(
        a_request(:delete, "#{base_url}/accounts/xyz").with(body: hash_including('force' => true))
      ).to have_been_made
    end

    it 'raises when a successful HTTP response contains an error envelope' do
      stub_request(:delete, "#{base_url}/accounts/xyz")
        .to_return(json_response({ 'status' => 409, 'data' => nil, 'message' => 'Account is in use' }))

      expect { resource.delete(account_id_override: 'xyz') }
        .to raise_error(Assinafy::ApiError) { |error| expect(error.status_code).to eq(409) }
    end
  end

  describe '#theme' do
    it 'GETs /accounts/{id}/theme' do
      stub_request(:get, "#{base_url}/accounts/acc/theme")
        .to_return(api_envelope({ 'account_name' => 'MT', 'primary_color' => '2072b9' }))

      expect(resource.theme['account_name']).to eq('MT')
    end
  end

  describe '#stats' do
    it 'GETs /accounts/{id}/stats with granularity/month query params' do
      stub_request(:get, "#{base_url}/accounts/acc/stats")
        .with(query: { 'granularity' => 'monthly', 'month' => '2026-06' })
        .to_return(api_envelope([{ 'period' => '2026-06' }]))

      result = resource.stats(granularity: 'monthly', month: '2026-06')
      expect(result.first['period']).to eq('2026-06')
    end

    it 'rejects a malformed successful response' do
      stub_request(:get, "#{base_url}/accounts/acc/stats")
        .to_return(api_envelope({ 'period' => '2026-06' }))

      expect { resource.stats }.to raise_error(Assinafy::Error, /Array data payload/)
    end
  end

  describe '#download_logo' do
    it 'returns the raw logo bytes' do
      stub_request(:get, "#{base_url}/accounts/acc/logo")
        .to_return(status: 200, body: "\x89PNG binary", headers: { 'Content-Type' => 'image/png' })

      bytes = resource.download_logo
      expect(bytes).to include('PNG')
      expect(bytes.encoding).to eq(Encoding::ASCII_8BIT)
    end
  end

  describe '#upload_logo' do
    it 'POSTs the logo as multipart/form-data' do
      stub_request(:post, "#{base_url}/accounts/acc/logo")
        .to_return(api_envelope({ 'mime_type' => 'image/png', 'version' => 1 }))

      result = resource.upload_logo(buffer: 'binary', file_name: 'logo.png')
      expect(result['mime_type']).to eq('image/png')
      expect(
        a_request(:post, "#{base_url}/accounts/acc/logo")
          .with(headers: { 'Content-Type' => %r{\Amultipart/form-data} })
      ).to have_been_made
    end
  end

  describe '#delete_logo' do
    it 'DELETEs the logo and returns nil' do
      stub_request(:delete, "#{base_url}/accounts/acc/logo").to_return(api_envelope([]))

      expect(resource.delete_logo).to be_nil
    end
  end
end
