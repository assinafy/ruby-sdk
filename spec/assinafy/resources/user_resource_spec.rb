# frozen_string_literal: true

RSpec.describe Assinafy::Resources::UserResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }
  let(:resource)   { described_class.new(connection) }

  describe '#me' do
    it 'returns the direct AuthUser shape documented by OpenAPI' do
      stub_request(:get, "#{base_url}/users/self")
        .to_return(api_envelope({ 'id' => 'u1', 'email' => 'user@example.com' }))

      expect(resource.me['id']).to eq('u1')
    end

    it 'GETs /users/self and returns { user:, accounts: }' do
      stub_request(:get, "#{base_url}/users/self")
        .to_return(api_envelope({ 'user'     => { 'id' => 'u1', 'email' => 'user@example.com' },
                                  'accounts' => [{ 'id' => 'acc' }] }))

      result = resource.me
      expect(result['user']['email']).to eq('user@example.com')
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

    it 'rejects a malformed successful response' do
      stub_request(:get, "#{base_url}/users/self/stats")
        .to_return(api_envelope({ 'period' => '2026-06' }))

      expect { resource.stats }.to raise_error(Assinafy::Error, /Array data payload/)
    end
  end

  describe 'notification preferences' do
    let(:preference_codes) do
      %w[
        DocumentCompleted
        SignerDeclined
        DocumentCancelled
        DocumentAboutToExpire
        DocumentExpired
        DocumentExpirationReset
        DocumentProcessingFailed
        TemplateProcessingFailed
        SignerWhatsappFailed
        ContractRenewalNotice
        ContractExpiring
        ContractExpired
        ContractRenewed
      ]
    end

    let(:preferences) do
      preference_codes.to_h { |code| [code, true] }
    end

    it 'pins the thirteen documented codes independently of the implementation constant' do
      expect(described_class::NOTIFICATION_PREFERENCE_CODES).to eq(preference_codes)
    end

    it 'GETs and returns the full preference map' do
      stub_request(:get, "#{base_url}/users/self/notification-preferences")
        .to_return(api_envelope(preferences))

      expect(resource.notification_preferences).to eq(preferences)
    end

    it 'PUTs a validated partial preference map' do
      stub_request(:put, "#{base_url}/users/self/notification-preferences")
        .with(body: { 'SignerDeclined' => false })
        .to_return(api_envelope(preferences.merge('SignerDeclined' => false)))

      result = resource.update_notification_preferences(SignerDeclined: false)
      expect(result['SignerDeclined']).to be(false)
    end

    it 'accepts contract lifecycle preferences' do
      stub_request(:put, "#{base_url}/users/self/notification-preferences")
        .with(body: { 'ContractRenewalNotice' => false })
        .to_return(api_envelope(preferences.merge('ContractRenewalNotice' => false)))

      result = resource.update_notification_preferences(ContractRenewalNotice: false)
      expect(result['ContractRenewalNotice']).to be(false)
    end

    it 'rejects empty, unknown, and non-boolean values before requesting' do
      expect { resource.update_notification_preferences({}) }.to raise_error(Assinafy::ValidationError)
      expect { resource.update_notification_preferences(Unknown: true) }.to raise_error(Assinafy::ValidationError)
      expect do
        resource.update_notification_preferences(DocumentCompleted: 1)
      end.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#stats parameter validation' do
    it 'rejects unknown granularity, malformed months, and daily stats without a month before the network' do
      resource = described_class.new(build_test_connection)

      expect { resource.stats(granularity: 'weekly') }.to raise_error(Assinafy::ValidationError, /granularity/)
      expect { resource.stats(month: '2026-13') }.to raise_error(Assinafy::ValidationError, /YYYY-MM/)
      expect { resource.stats(granularity: 'daily') }.to raise_error(Assinafy::ValidationError, /month is required/)

      expect(a_request(:get, "#{base_url}/users/self/stats")).not_to have_been_made
    end
  end

  describe 'push preferences' do
    let(:preferences) do
      %w[SignerViewed SignerSigned DocumentCompleted SignerDeclined DocumentAboutToExpire
         DocumentExpired SignerIdentityReviewRequired SignerWhatsappFailed].to_h { |code| [code, true] }
    end

    it 'reads the separate push preference map with workspace credentials' do
      stub_request(:get, "#{base_url}/users/self/push-preferences")
        .with(headers: { 'X-Api-Key' => 'test-key' }).to_return(api_envelope(preferences))

      expect(resource.push_preferences).to eq(preferences)
    end

    it 'sends a partial map and preserves false' do
      stub_request(:put, "#{base_url}/users/self/push-preferences")
        .with(body: { 'SignerViewed' => false })
        .to_return(api_envelope(preferences.merge('SignerViewed' => false)))

      expect(resource.update_push_preferences(SignerViewed: false)).to eq(preferences.merge('SignerViewed' => false))
    end

    it 'rejects email-only, empty, unknown, and non-boolean preferences locally' do
      [{}, { ContractRenewed: true }, { Unknown: true }, { SignerViewed: nil }, { SignerViewed: 1 }].each do |value|
        expect { resource.update_push_preferences(value) }.to raise_error(Assinafy::ValidationError)
      end
      expect(a_request(:put, "#{base_url}/users/self/push-preferences")).not_to have_been_made
    end
  end
end
