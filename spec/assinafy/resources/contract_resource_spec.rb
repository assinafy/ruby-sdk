# frozen_string_literal: true

RSpec.describe Assinafy::Resources::ContractResource do
  let(:base_url) { 'https://api.assinafy.com.br/v1' }
  let(:resource) { described_class.new(build_test_connection(base_url), 'acc') }
  let(:contract) do
    {
      'resource' => 'document_contract', 'document_id' => 'doc-1', 'status' => 'active',
      'end_date' => '2027-10-31', 'term' => 1, 'external_references' => []
    }
  end
  let(:contract_url) { "#{base_url}/accounts/acc/documents/doc-1/contract" }

  describe '#list' do
    it 'sends documented filters and returns pagination metadata' do
      headers = {
        'X-Pagination-Current-Page' => '1',
        'X-Pagination-Per-Page'     => '20',
        'X-Pagination-Total-Count'  => '1',
        'X-Pagination-Page-Count'   => '1'
      }
      stub_request(:get, "#{base_url}/accounts/acc/contracts")
        .with(query: hash_including('status' => 'active,expired', 'per-page' => '20',
                                    'ending_within_days' => '30', 'expand' => 'document'))
        .to_return(json_response({ status: 200, data: [contract] }, headers: headers))

      result = resource.list(status: %w[active expired], per_page: 20,
                             ending_within_days: 30, expand: 'document')

      expect(result).to eq(data: [contract], meta: { current_page: 1, per_page: 20, total: 1, last_page: 1 })
    end

    it 'rejects unknown, mistyped, and invalid filters before a request' do
      invalid = [
        { status: ['unknown'] }, { ending_within_days: -1 }, { sort: 'name' },
        { expand: 'assignment' }, { end_date_from: '2026-02-30' }, { per_page: 101 }, { unknown: true }
      ]

      invalid.each do |filters|
        expect { resource.list(filters) }.to raise_error(Assinafy::ValidationError)
      end
      expect(a_request(:get, "#{base_url}/accounts/acc/contracts")).not_to have_been_made
    end
  end

  describe '#get' do
    it 'returns the unwrapped contract' do
      stub_request(:get, contract_url).to_return(api_envelope(contract))

      expect(resource.get('doc-1')).to eq(contract)
    end

    it 'returns nil when the document has no contract terms' do
      stub_request(:get, contract_url).to_return(json_response({ status: 404, message: 'No contract' }, status: 404))

      expect(resource.get('doc-1')).to be_nil
    end
  end

  describe '#update' do
    it 'preserves explicit nulls and nested payload keys' do
      stub_request(:put, contract_url)
        .with(body: {
          'counterparty_name'   => nil,
          'auto_renew'          => nil,
          'metadata'            => { 'crm_stage' => 'won' },
          'external_references' => [{ 'system' => 'hubspot', 'id' => '98765' }]
        })
        .to_return(api_envelope(contract.merge('counterparty_name' => nil)))

      result = resource.update('doc-1', counterparty_name: nil, auto_renew: nil, metadata: { crm_stage: 'won' },
                                         external_references: [{ system: 'hubspot', id: '98765' }])

      expect(result['counterparty_name']).to be_nil
    end

    it 'links an amendment using the documented fields' do
      amendment = { 'resource' => 'document_contract_amendment', 'document_id' => 'doc-1', 'status' => 'pending' }
      stub_request(:put, contract_url)
        .with(body: { 'parent_document_id' => 'parent-1', 'relation_type' => 'amendment', 'value' => 130_000 })
        .to_return(api_envelope(amendment))

      expect(resource.update('doc-1', parent_document_id: 'parent-1',
                                       relation_type: 'amendment', value: 130_000)).to eq(amendment)
    end

    it 'rejects empty, unknown, and invalid contract fields before a request' do
      invalid = [
        {}, { unknown: true }, { status: 'closed' }, { currency: 'REAL' },
        { start_date: '2027-02-30' }, { start_date: '0999-12-31' }, { value: 1.234 },
        { renewal_term_months: 0 }, { auto_renew: 'yes' },
        { updated_at: '2026-10-23' },
        { metadata: { invalid: 1 } }, { external_references: [{ system: 'bad value', id: '1' }] }
      ]

      invalid.each do |payload|
        expect { resource.update('doc-1', payload) }.to raise_error(Assinafy::ValidationError)
      end
      expect(a_request(:put, contract_url)).not_to have_been_made
    end
  end

  describe '#related' do
    it 'fetches the root family from any related document' do
      stub_request(:get, "#{contract_url}/related")
        .to_return(api_envelope(contract.merge('amendments' => [{ 'document_id' => 'amendment-1' }])))

      expect(resource.related('doc-1')['amendments'].first['document_id']).to eq('amendment-1')
    end
  end

  describe '#renew' do
    it 'posts an idempotent term-based renewal and preserves a null value' do
      stub_request(:post, "#{contract_url}/renew")
        .with(body: { 'term' => 1, 'value' => nil, 'updated_at' => '2026-10-23T12:00:00Z' })
        .to_return(api_envelope(contract.merge('term' => 2, 'value' => nil)))

      result = resource.renew('doc-1', term: 1, value: nil, updated_at: '2026-10-23T12:00:00Z')

      expect(result).to include('term' => 2, 'value' => nil)
    end

    it 'requires a term or end date before a request' do
      expect { resource.renew('doc-1', value: 10) }.to raise_error(Assinafy::ValidationError)
      expect(a_request(:post, "#{contract_url}/renew")).not_to have_been_made
    end
  end

  describe '#terminate' do
    it 'posts the optional reason' do
      stub_request(:post, "#{contract_url}/terminate")
        .with(body: { 'reason' => 'Supplier replaced' })
        .to_return(api_envelope(contract.merge('status' => 'terminated')))

      expect(resource.terminate('doc-1', reason: 'Supplier replaced')['status']).to eq('terminated')
    end

    it 'allows an empty body but rejects an overlong reason' do
      stub_request(:post, "#{contract_url}/terminate").with(body: {}).to_return(api_envelope(contract))

      expect(resource.terminate('doc-1')).to eq(contract)
      expect { resource.terminate('doc-1', reason: 'x' * 501) }.to raise_error(Assinafy::ValidationError)
    end
  end

  it 'rejects unsafe IDs before any request' do
    expect { resource.get('../doc') }.to raise_error(Assinafy::ValidationError)
    expect { resource.update('doc-1', { status: 'active' }, '../acc') }.to raise_error(Assinafy::ValidationError)
  end
end
