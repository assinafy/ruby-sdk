# frozen_string_literal: true

require 'openssl'

RSpec.describe Assinafy::Support::WebhookVerifier do
  let(:secret)    { 'super-secret' }
  let(:payload)   { JSON.generate({ 'event' => 'document_ready', 'data' => { 'document_id' => 'doc-1' } }) }
  let(:signature) { OpenSSL::HMAC.hexdigest('SHA256', secret, payload) }
  let(:verifier)  { described_class.new(secret) }

  describe '#verify' do
    it 'returns true for a valid HMAC-SHA256 signature' do
      expect(verifier.verify(payload, signature)).to be true
    end

    it 'returns false for a mismatched signature' do
      expect(verifier.verify(payload, 'deadbeef')).to be false
    end

    it 'returns false when no secret is configured' do
      v = described_class.new(nil)
      expect(v.verify(payload, signature)).to be false
    end

    it 'returns false when signature is empty' do
      expect(verifier.verify(payload, '')).to be false
    end

    it 'trims whitespace from the provided signature' do
      expect(verifier.verify(payload, "  #{signature}  ")).to be true
    end
  end

  describe '#extract_event' do
    it 'parses valid JSON payloads' do
      result = verifier.extract_event(payload)
      expect(result).to eq({ 'event' => 'document_ready', 'data' => { 'document_id' => 'doc-1' } })
    end

    it 'returns nil for malformed JSON' do
      expect(verifier.extract_event('{not json')).to be_nil
    end

    it 'returns nil for non-object JSON' do
      expect(verifier.extract_event('[1, 2, 3]')).to be_nil
    end
  end

  describe '#event_type' do
    it 'extracts the event name from the event key' do
      event = verifier.extract_event(payload)
      expect(verifier.event_type(event)).to eq('document_ready')
    end

    it 'falls back to the type key' do
      expect(verifier.event_type({ 'type' => 'signer_signed_document' })).to eq('signer_signed_document')
    end

    it 'returns nil for nil input' do
      expect(verifier.event_type(nil)).to be_nil
    end
  end

  describe '#event_data' do
    it 'extracts data from the data key' do
      event = verifier.extract_event(payload)
      expect(verifier.event_data(event)).to eq({ 'document_id' => 'doc-1' })
    end

    it 'falls back to the object key' do
      expect(verifier.event_data({ 'object' => { 'id' => '1' } })).to eq({ 'id' => '1' })
    end

    it 'returns an empty hash for nil input' do
      expect(verifier.event_data(nil)).to eq({})
    end
  end
end
