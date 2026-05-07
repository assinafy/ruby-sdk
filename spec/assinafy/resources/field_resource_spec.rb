# frozen_string_literal: true

RSpec.describe Assinafy::Resources::FieldResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }
  let(:resource)   { described_class.new(connection, 'acc') }

  describe '#create' do
    it 'posts to /accounts/{id}/fields' do
      stub_request(:post, "#{base_url}/accounts/acc/fields")
        .to_return(api_envelope({ 'id' => 'field-1' }))

      result = resource.create(type: 'text', name: 'Field Name')

      expect(result['id']).to eq('field-1')
      expect(
        a_request(:post, "#{base_url}/accounts/acc/fields")
          .with(body: hash_including('type' => 'text', 'name' => 'Field Name'))
      ).to have_been_made
    end
  end

  describe '#list' do
    it 'keeps documented underscore query params' do
      stub_request(:get, "#{base_url}/accounts/acc/fields")
        .with(query: hash_including('include_inactive' => 'true'))
        .to_return(api_envelope([]))

      resource.list(include_inactive: true)

      expect(a_request(:get, "#{base_url}/accounts/acc/fields")
        .with(query: hash_including('include_inactive' => 'true'))).to have_been_made
    end
  end

  describe '#validate' do
    it 'uses signer-access-code as query parameter' do
      stub_request(:post, "#{base_url}/accounts/acc/fields/field-1/validate")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(api_envelope({ 'success' => true }))

      result = resource.validate('field-1', 'value', signer_access_code: 'code')

      expect(result['success']).to be true
    end
  end

  describe '#types' do
    it 'calls /field-types' do
      stub_request(:get, "#{base_url}/field-types").to_return(api_envelope([]))

      resource.types

      expect(a_request(:get, "#{base_url}/field-types")).to have_been_made
    end
  end
end
