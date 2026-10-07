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
end
