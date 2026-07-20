# frozen_string_literal: true

RSpec.describe Assinafy::Resources::UserResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }
  let(:resource)   { described_class.new(connection) }

  describe '#me' do
    it 'GETs /users/self and returns { user:, accounts: }' do
      stub_request(:get, "#{base_url}/users/self")
        .to_return(api_envelope({ 'user'     => { 'id' => 'u1', 'email' => 'bill@febacapital.com' },
                                  'accounts' => [{ 'id' => 'acc' }] }))

      result = resource.me
      expect(result['user']['email']).to eq('bill@febacapital.com')
      expect(result['accounts'].first['id']).to eq('acc')
    end
  end

  describe '#stats' do
    it 'GETs /users/self/stats with query params' do
      stub_request(:get, "#{base_url}/users/self/stats")
        .with(query: { 'granularity' => 'monthly' })
        .to_return(api_envelope([{ 'period' => '2026-06' }]))

      expect(resource.stats(granularity: 'monthly').first['period']).to eq('2026-06')
    end
  end
end
