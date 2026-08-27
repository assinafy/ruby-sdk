# frozen_string_literal: true

RSpec.describe Assinafy::Resources::AssignmentResource do
  let(:base_url) { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }

  def without_workspace_auth?(request)
    !request.headers.key?('X-Api-Key') && !request.headers.key?('Authorization')
  end

  describe '#list' do
    it 'GETs /assignments with the camelCase accountId query param' do
      resource = described_class.new(connection, 'acc')
      stub_request(:get, "#{base_url}/assignments")
        .with(query: hash_including('accountId' => 'acc'))
        .to_return(api_envelope([{ 'id' => 'asg-1', 'method' => 'virtual' }]))

      result = resource.list
      expect(result[:data].first['id']).to eq('asg-1')
      expect(
        a_request(:get, "#{base_url}/assignments").with(query: hash_including('accountId' => 'acc'))
      ).to have_been_made
    end

    it 'rejects non-Hash query parameters before making a request' do
      resource = described_class.new(connection, 'acc')

      expect { resource.list([]) }.to raise_error(Assinafy::ValidationError, /query parameters/)
      expect(a_request(:get, "#{base_url}/assignments")).not_to have_been_made
    end
  end

  describe '.build_payload' do
    it 'rejects invalid payloads and methods' do
      expect { described_class.build_payload([]) }.to raise_error(Assinafy::ValidationError)
      expect do
        described_class.build_payload(method: 'typo', signers: ['s1'])
      end.to raise_error(Assinafy::ValidationError)
    end

    it 'omits an empty signers array from collect payloads' do
      expect(described_class.build_payload(method: 'collect', entries: [{ page_id: 'p1', fields: [] }])).to eq(
        'method' => 'collect', 'entries' => [{ 'page_id' => 'p1', 'fields' => [] }]
      )
    end

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

    it 'preserves documented sequential signing steps' do
      body = described_class.build_payload(signers: [{ id: 'a', step: 1 }])
      expect(body['signers']).to eq([{ 'id' => 'a', 'step' => 1 }])
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

    it 'puts to the documented signer resend endpoint' do
      path = "#{base_url}/documents/doc/assignments/asg/signers/sig/resend"
      stub_request(:put, path).to_return(api_envelope({ 'is_sent' => true }))

      resource = described_class.new(connection, 'acc')
      result   = resource.resend_notification('doc', 'asg', 'sig')

      expect(result['is_sent']).to be(true)
      expect(a_request(:put, path)).to have_been_made
    end
  end

  describe '#estimate_resend_cost' do
    it 'posts to the signer estimate-resend-cost endpoint' do
      path = "#{base_url}/documents/doc/assignments/asg/signers/sig/estimate-resend-cost"
      stub_request(:post, path).to_return(api_envelope({ 'total' => 0.2 }))

      resource = described_class.new(connection, 'acc')
      result   = resource.estimate_resend_cost('doc', 'asg', 'sig')

      expect(result['total']).to eq(0.2)
      expect(a_request(:post, path)).to have_been_made
    end
  end

  describe '#reset_expiration' do
    it 'sends the new expiration timestamp in the body' do
      path = "#{base_url}/documents/doc/assignments/asg/reset-expiration"
      stub_request(:put, path).to_return(api_envelope({ 'id' => 'asg' }))

      resource = described_class.new(connection, 'acc')
      resource.reset_expiration('doc', 'asg', '2026-12-31T23:59:00Z')

      expect(
        a_request(:put, path).with(body: { 'expires_at' => '2026-12-31T23:59:00Z' })
      ).to have_been_made
    end

    it 'sends nil as an explicit JSON null rather than dropping the key' do
      path = "#{base_url}/documents/doc/assignments/asg/reset-expiration"
      stub_request(:put, path).to_return(api_envelope({ 'id' => 'asg' }))

      resource = described_class.new(connection, 'acc')
      resource.reset_expiration('doc', 'asg', nil)

      expect(a_request(:put, path).with(body: { 'expires_at' => nil })).to have_been_made
    end
  end

  describe '#whatsapp_notifications' do
    it 'gets the documented whatsapp-notifications endpoint' do
      path = "#{base_url}/documents/doc/assignments/asg/whatsapp-notifications"
      stub_request(:get, path).to_return(api_envelope([{ 'signer_id' => 'sig' }]))

      resource = described_class.new(connection, 'acc')
      result   = resource.whatsapp_notifications('doc', 'asg')

      expect(result.first['signer_id']).to eq('sig')
      expect(a_request(:get, path)).to have_been_made
    end

    it 'rejects a malformed non-Array success payload' do
      path = "#{base_url}/documents/doc/assignments/asg/whatsapp-notifications"
      stub_request(:get, path).to_return(api_envelope({ 'signer_id' => 'sig' }))

      resource = described_class.new(connection, 'acc')
      expect { resource.whatsapp_notifications('doc', 'asg') }
        .to raise_error(Assinafy::Error, /Array data payload/)
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
        .with(query: hash_including('signer-access-code' => 'code')) do |request|
          without_workspace_auth?(request)
        end
        .to_return(api_envelope({ 'id' => 'doc-1' }))

      resource = described_class.new(connection, 'acc')
      result = resource.signer_document(signer_access_code: 'code')

      expect(result['id']).to eq('doc-1')
      expect(
        a_request(:get, "#{base_url}/sign").with(query: hash_including('signer-access-code' => 'code'))
      ).to have_been_made
    end

    it 'rejects nil and blank access codes before making a request' do
      resource = described_class.new(connection, 'acc')

      [nil, '', ' '].each do |code|
        expect { resource.signer_document(signer_access_code: code) }
          .to raise_error(Assinafy::ValidationError, /Signer access code/)
      end
      expect(a_request(:get, "#{base_url}/sign")).not_to have_been_made
    end

    it 'rejects a non-boolean terms flag before making a request' do
      resource = described_class.new(connection, 'acc')

      expect do
        resource.signer_document(signer_access_code: 'code', has_accepted_terms: 'true')
      end.to raise_error(Assinafy::ValidationError, /has_accepted_terms/)
      expect(a_request(:get, "#{base_url}/sign")).not_to have_been_made
    end
  end

  describe '#sign' do
    it 'maps snake_case item keys to the camelCase keys the API expects' do
      stub_request(:post, "#{base_url}/documents/doc/assignments/asg")
        .with(query: hash_including('signer-access-code' => 'code')) do |request|
          without_workspace_auth?(request)
        end
        .to_return(api_envelope([]))

      resource = described_class.new(connection, 'acc')
      resource.sign(
        'doc',
        'asg',
        [{ item_id: 'i1', field_id: 'f1', page_id: 'p1', value: 'v1' }],
        signer_access_code: 'code'
      )

      expect(
        a_request(:post, "#{base_url}/documents/doc/assignments/asg")
          .with(
            query: hash_including('signer-access-code' => 'code'),
            body:  [{ 'itemId' => 'i1', 'fieldId' => 'f1', 'pageId' => 'p1', 'value' => 'v1' }]
          )
      ).to have_been_made
    end

    it 'passes through already-camelCase item keys unchanged' do
      stub_request(:post, "#{base_url}/documents/doc/assignments/asg")
        .with(query: hash_including('signer-access-code' => 'code')) do |request|
          without_workspace_auth?(request)
        end
        .to_return(api_envelope([]))

      resource = described_class.new(connection, 'acc')
      resource.sign(
        'doc',
        'asg',
        [{ 'itemId' => 'i1', 'fieldId' => 'f1', 'pageId' => 'p1', 'value' => 'v1' }],
        signer_access_code: 'code'
      )

      expect(
        a_request(:post, "#{base_url}/documents/doc/assignments/asg")
          .with(
            query: hash_including('signer-access-code' => 'code'),
            body:  [{ 'itemId' => 'i1', 'fieldId' => 'f1', 'pageId' => 'p1', 'value' => 'v1' }]
          )
      ).to have_been_made
    end

    it 'requires at least one assignment item' do
      resource = described_class.new(connection, 'acc')
      expect do
        resource.sign('doc', 'asg', [], signer_access_code: 'code')
      end.to raise_error(Assinafy::ValidationError)
    end

    it 'rejects non-Hash items and blank access codes without making a request' do
      resource = described_class.new(connection, 'acc')

      expect { resource.sign('doc', 'asg', ['bad'], signer_access_code: 'code') }
        .to raise_error(Assinafy::ValidationError, /Assignment item/)
      expect do
        resource.sign(
          'doc', 'asg',
          [{ item_id: 'item', field_id: 'field', page_id: 'page', value: 'Signed' }],
          signer_access_code: ' '
        )
      end.to raise_error(Assinafy::ValidationError, /Signer access code/)
      expect(a_request(:post, "#{base_url}/documents/doc/assignments/asg")).not_to have_been_made
    end

    it 'requires all documented item fields and safe String IDs before making a request' do
      resource = described_class.new(connection, 'acc')

      [{ item_id: 'item', field_id: 'field', page_id: 'page' },
       { item_id: 'item', field_id: 'field', page_id: 'page', value: 123 },
       { item_id: '../bad', field_id: 'field', page_id: 'page', value: 'Signed' }].each do |item|
        expect { resource.sign('doc', 'asg', [item], signer_access_code: 'code') }
          .to raise_error(Assinafy::ValidationError)
      end
      expect(a_request(:post, "#{base_url}/documents/doc/assignments/asg")).not_to have_been_made
    end
  end

  describe '#decline' do
    it 'calls the documented reject endpoint' do
      stub_request(:put, "#{base_url}/documents/doc/assignments/asg/reject")
        .with(query: hash_including('signer-access-code' => 'code')) do |request|
          without_workspace_auth?(request)
        end
        .to_return(api_envelope([]))

      resource = described_class.new(connection, 'acc')
      resource.decline('doc', 'asg', decline_reason: 'No', signer_access_code: 'code')

      expect(
        a_request(:put, "#{base_url}/documents/doc/assignments/asg/reject")
          .with(query: hash_including('signer-access-code' => 'code'))
      ).to have_been_made
    end

    it 'rejects a nil access code without making a request' do
      resource = described_class.new(connection, 'acc')

      expect do
        resource.decline('doc', 'asg', decline_reason: 'No', signer_access_code: nil)
      end.to raise_error(Assinafy::ValidationError, /Signer access code/)
      expect(a_request(:put, "#{base_url}/documents/doc/assignments/asg/reject")).not_to have_been_made
    end

    it 'rejects a non-String or blank decline reason before making a request' do
      resource = described_class.new(connection, 'acc')

      [nil, ' ', 123].each do |reason|
        expect do
          resource.decline('doc', 'asg', decline_reason: reason, signer_access_code: 'code')
        end.to raise_error(Assinafy::ValidationError, /Decline reason/)
      end
      expect(a_request(:put, "#{base_url}/documents/doc/assignments/asg/reject")).not_to have_been_made
    end
  end
end
