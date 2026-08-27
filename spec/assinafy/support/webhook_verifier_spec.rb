# frozen_string_literal: true

require 'openssl'

RSpec.describe Assinafy::Support::WebhookVerifier do
  let(:secret) { 'super-secret' }
  # Real Assinafy v1 delivery envelope shape (top-level event/payload/subject/object).
  let(:event_hash) do
    {
      'id'         => 8,
      'event'      => 'assignment_created',
      'message'    => nil,
      'payload'    => { 'user_name' => 'John Smith', 'user_email' => 'john@example.com' },
      'origin'     => { 'ip' => '172.19.0.1', 'user-agent' => 'curl/8' },
      'created_at' => 1_705_312_250,
      'subject'    => { 'id' => 'usr1', 'name' => 'John Smith', 'type' => 'User' },
      'object'     => { 'id' => 'doc2', 'name' => '2.pdf', 'status' => 'pending_signature', 'type' => 'Document' },
      'account_id' => '1a'
    }
  end
  let(:payload)   { JSON.generate(event_hash) }
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

    it 'snapshots the secret supplied at construction' do
      mutable_secret = secret.dup
      stable_verifier = described_class.new(mutable_secret)
      mutable_secret.replace('changed')

      expect(stable_verifier.verify(payload, signature)).to be true
    end
  end

  describe '#extract_event' do
    it 'parses valid JSON payloads' do
      expect(verifier.extract_event(payload)).to eq(event_hash)
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
      expect(verifier.event_type(event_hash)).to eq('assignment_created')
    end

    it 'returns nil when there is no event key' do
      expect(verifier.event_type({ 'type' => 'whatever' })).to be_nil
    end

    it 'returns nil for nil input' do
      expect(verifier.event_type(nil)).to be_nil
    end
  end

  describe '#event_payload' do
    it 'returns the event-specific payload snapshot' do
      expect(verifier.event_payload(event_hash)).to eq('user_name' => 'John Smith', 'user_email' => 'john@example.com')
    end

    it 'returns nil when payload is absent (e.g. document_uploaded)' do
      expect(verifier.event_payload({ 'event' => 'document_uploaded', 'payload' => nil })).to be_nil
    end

    it 'returns nil for nil input' do
      expect(verifier.event_payload(nil)).to be_nil
    end
  end

  describe '#event_object' do
    it 'returns the acted-on entity' do
      expect(verifier.event_object(event_hash)).to include('id' => 'doc2', 'type' => 'Document')
    end

    it 'returns an empty hash when absent' do
      expect(verifier.event_object({})).to eq({})
    end
  end

  describe '#event_subject' do
    it 'returns the actor' do
      expect(verifier.event_subject(event_hash)).to include('id' => 'usr1', 'type' => 'User')
    end

    it 'returns an empty hash for nil input' do
      expect(verifier.event_subject(nil)).to eq({})
    end
  end

  describe '#event_data (deprecated)' do
    it 'returns payload when present' do
      expect(verifier.event_data(event_hash)).to eq('user_name' => 'John Smith', 'user_email' => 'john@example.com')
    end

    it 'falls back to object when payload is nil' do
      expect(verifier.event_data({ 'payload' => nil, 'object' => { 'id' => 'doc2' } })).to eq('id' => 'doc2')
    end

    it 'returns an empty hash for nil input' do
      expect(verifier.event_data(nil)).to eq({})
    end
  end
end
