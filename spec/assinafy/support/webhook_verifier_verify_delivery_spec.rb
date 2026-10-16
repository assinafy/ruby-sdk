# frozen_string_literal: true

RSpec.describe Assinafy::Support::WebhookVerifier, '#verify_delivery' do
  # Test vector from the Standard Webhooks reference libraries.
  let(:verifier) { described_class.new('whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw') }
  let(:time)     { 1_614_265_330 }
  let(:body)     { '{"test": 2432232314}' }
  let(:headers) do
    {
      'webhook-id'        => 'msg_p5jXN8AQM9LWM0D4loKWxJek',
      'webhook-timestamp' => time.to_s,
      'webhook-signature' => 'v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE='
    }
  end

  it 'accepts the reference signature' do
    expect(verifier.verify_delivery(body, headers, now: time)).to be true
  end

  it 'accepts Rack env and capitalized header names, and any matching entry' do
    rack = {
      'HTTP_WEBHOOK_ID'        => headers['webhook-id'],
      'HTTP_WEBHOOK_TIMESTAMP' => headers['webhook-timestamp'],
      'HTTP_WEBHOOK_SIGNATURE' => "v1,bm90LXRoaXM= #{headers['webhook-signature']}"
    }
    capitalized = headers.transform_keys { |key| key.split('-').map(&:capitalize).join('-') }

    expect(verifier.verify_delivery(body, rack, now: time)).to be true
    expect(verifier.verify_delivery(body, capitalized, now: time)).to be true
  end

  it 'rejects a tampered body, a stale timestamp, and missing headers' do
    expect(verifier.verify_delivery("#{body} ", headers, now: time)).to be false
    expect(verifier.verify_delivery(body, headers, now: time + 301)).to be false
    expect(verifier.verify_delivery(body, headers.except('webhook-id'), now: time)).to be false
  end

  it 'rejects secrets without the whsec_ prefix' do
    unprefixed = described_class.new('MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw')

    expect(unprefixed.verify_delivery(body, headers, now: time)).to be false
    expect(described_class.new(nil).verify_delivery(body, headers, now: time)).to be false
  end

  it 'accepts the tolerance boundary but rejects future and past replays outside it' do
    expect(verifier.verify_delivery(body, headers, now: time + 300)).to be true
    expect(verifier.verify_delivery(body, headers, now: time - 300)).to be true
    expect(verifier.verify_delivery(body, headers, now: time - 301)).to be false
  end

  it 'rejects malformed secrets, timestamps and signatures without raising' do
    ['', 'whsec_', 'whsec_%%invalid%%'].each do |secret|
      expect(described_class.new(secret).verify_delivery(body, headers, now: time)).to be false
    end
    ['invalid', '', nil].each do |timestamp|
      expect(verifier.verify_delivery(body, headers.merge('webhook-timestamp' => timestamp), now: time)).to be false
    end
    ['v2,placeholder', 'v1,%%invalid%%', '', nil].each do |signature|
      expect(verifier.verify_delivery(body, headers.merge('webhook-signature' => signature), now: time)).to be false
    end
  end

  it 'authenticates both the delivery ID and timestamp along with the body' do
    expect(verifier.verify_delivery(body, headers.merge('webhook-id' => 'other-message'), now: time)).to be false
    expect(verifier.verify_delivery(body, headers.merge('webhook-timestamp' => (time + 1).to_s), now: time)).to be false
  end
end
