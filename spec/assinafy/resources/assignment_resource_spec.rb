# frozen_string_literal: true

RSpec.describe Assinafy::Resources::AssignmentResource do
  let(:base_url) { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }

  describe '.build_payload' do
    it 'normalises string signer ids into {id} hashes' do
      body = described_class.build_payload(signers: %w[a b])
      expect(body).to eq({ 'method' => 'virtual', 'signers' => [{ 'id' => 'a' }, { 'id' => 'b' }] })
    end

    it 'accepts legacy signer_ids payload' do
      expect(described_class.build_payload(signer_ids: ['a'])).to eq(
        { 'method' => 'virtual', 'signers' => [{ 'id' => 'a' }] }
      )
    end

    it 'accepts legacy signerIds payload' do
      expect(described_class.build_payload(signerIds: ['b'])).to eq(
        { 'method' => 'virtual', 'signers' => [{ 'id' => 'b' }] }
      )
    end

    it 'accepts objects with id or signer_id' do
      body = described_class.build_payload(signers: [{ id: 'a' }, { signer_id: 'b' }])
      expect(body['signers']).to eq([{ 'id' => 'a' }, { 'id' => 'b' }])
    end

    it 'allows estimation payloads without signer ids when methods are supplied' do
      body = described_class.build_payload(
        { signers: [{ verification_method: 'Whatsapp' }, {}] },
        { allow_signers_without_id: true }
      )
      expect(body).to eq(
        { 'method' => 'virtual', 'signers' => [{ 'verification_method' => 'Whatsapp' }, {}] }
      )
    end

    it 'includes optional fields when provided' do
      body = described_class.build_payload(
        signers:        ['a'],
        message:        'hi',
        expires_at:     '2024-12-31',
        copy_receivers: ['c']
      )
      expect(body['message']).to        eq('hi')
      expect(body['expires_at']).to     eq('2024-12-31')
      expect(body['copy_receivers']).to eq(['c'])
    end

    it 'omits nil/falsy optional fields' do
      body = described_class.build_payload(signers: ['a'])
      expect(body).not_to have_key('message')
      expect(body).not_to have_key('expires_at')
    end

    it 'raises ValidationError on empty signers array' do
      expect { described_class.build_payload(signers: []) }.to raise_error(Assinafy::ValidationError)
    end

    it 'allows collect payloads with entries and no top-level signers' do
      body = described_class.build_payload(method: 'collect', entries: [{ page_id: 'page', fields: [] }])
      expect(body['entries']).to eq([{ 'page_id' => 'page', 'fields' => [] }])
    end

    it 'raises ValidationError on invalid signer reference (empty hash without allow flag)' do
      expect { described_class.build_payload(signers: [{}]) }.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#create' do
    it 'posts to /documents/{id}/assignments with normalised body' do
      stub_request(:post, "#{base_url}/documents/doc-1/assignments")
        .to_return(api_envelope({ 'id' => 'assignment-1' }))

      resource = described_class.new(connection, 'acc')
      result   = resource.create('doc-1', { signers: %w[s1 s2] })

      expect(result['id']).to eq('assignment-1')
      expect(
        a_request(:post, "#{base_url}/documents/doc-1/assignments")
          .with(body: { 'method' => 'virtual', 'signers' => [{ 'id' => 's1' }, { 'id' => 's2' }] })
      ).to have_been_made
    end
  end

  describe '#resend_notification' do
    it 'raises ValidationError when document ID is empty' do
      resource = described_class.new(connection, 'acc')
      expect { resource.resend_notification('', 'a', 's') }.to raise_error(Assinafy::ValidationError)
    end

    it 'raises ValidationError when assignment ID is empty' do
      resource = described_class.new(connection, 'acc')
      expect { resource.resend_notification('d', '', 's') }.to raise_error(Assinafy::ValidationError)
    end

    it 'raises ValidationError when signer ID is empty' do
      resource = described_class.new(connection, 'acc')
      expect { resource.resend_notification('d', 'a', '') }.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#estimate_cost' do
    it 'accepts signer descriptors without ids and sends correct body' do
      stub_request(:post, "#{base_url}/documents/doc-1/assignments/estimate-cost")
        .to_return(api_envelope({ 'total_credits' => 0.45 }))

      resource = described_class.new(connection, 'acc')
      resource.estimate_cost('doc-1', { signers: [{ verification_method: 'Whatsapp' }] })

      expect(
        a_request(:post, "#{base_url}/documents/doc-1/assignments/estimate-cost")
          .with(body: { 'method' => 'virtual', 'signers' => [{ 'verification_method' => 'Whatsapp' }] })
      ).to have_been_made
    end
  end

  describe '#signer_document' do
    it 'calls GET /sign with signer-access-code' do
      stub_request(:get, "#{base_url}/sign")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(api_envelope({ 'id' => 'doc-1' }))

      resource = described_class.new(connection, 'acc')
      result = resource.signer_document(signer_access_code: 'code')

      expect(result['id']).to eq('doc-1')
    end
  end

  describe '#decline' do
    it 'calls the documented reject endpoint' do
      stub_request(:put, "#{base_url}/documents/doc/assignments/asg/reject")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(api_envelope([]))

      resource = described_class.new(connection, 'acc')
      resource.decline('doc', 'asg', decline_reason: 'No', signer_access_code: 'code')

      expect(
        a_request(:put, "#{base_url}/documents/doc/assignments/asg/reject")
          .with(query: hash_including('signer-access-code' => 'code'))
      ).to have_been_made
    end
  end
end
