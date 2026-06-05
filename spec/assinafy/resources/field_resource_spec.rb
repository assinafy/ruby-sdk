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

  describe '#get' do
    it 'gets /accounts/{id}/fields/{field_id}' do
      stub_request(:get, "#{base_url}/accounts/acc/fields/field-1")
        .to_return(api_envelope({ 'id' => 'field-1' }))

      result = resource.get('field-1')

      expect(result['id']).to eq('field-1')
      expect(a_request(:get, "#{base_url}/accounts/acc/fields/field-1")).to have_been_made
    end
  end

  describe '#update' do
    it 'puts to /accounts/{id}/fields/{field_id}' do
      stub_request(:put, "#{base_url}/accounts/acc/fields/field-1")
        .to_return(api_envelope({ 'id' => 'field-1' }))

      result = resource.update('field-1', name: 'New Field Name')

      expect(result['id']).to eq('field-1')
      expect(
        a_request(:put, "#{base_url}/accounts/acc/fields/field-1")
          .with(body: hash_including('name' => 'New Field Name'))
      ).to have_been_made
    end
  end

  describe '#delete' do
    it 'deletes /accounts/{id}/fields/{field_id} and returns nil' do
      stub_request(:delete, "#{base_url}/accounts/acc/fields/field-1")
        .to_return(api_envelope([]))

      result = resource.delete('field-1')

      expect(result).to be_nil
      expect(a_request(:delete, "#{base_url}/accounts/acc/fields/field-1")).to have_been_made
    end
  end

  describe '#validate' do
    it 'posts the value to /accounts/{id}/fields/{field_id}/validate' do
      stub_request(:post, "#{base_url}/accounts/acc/fields/field-1/validate")
        .to_return(api_envelope({ 'success' => true }))

      result = resource.validate('field-1', 'Some text')

      expect(result['success']).to be true
      expect(
        a_request(:post, "#{base_url}/accounts/acc/fields/field-1/validate")
          .with(body: hash_including('value' => 'Some text'))
      ).to have_been_made
    end

    it 'uses signer-access-code as query parameter' do
      stub_request(:post, "#{base_url}/accounts/acc/fields/field-1/validate")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(api_envelope({ 'success' => true }))

      result = resource.validate('field-1', 'value', signer_access_code: 'code')

      expect(result['success']).to be true
      expect(a_request(:post, "#{base_url}/accounts/acc/fields/field-1/validate")
        .with(query: hash_including('signer-access-code' => 'code'))).to have_been_made
    end
  end

  describe '#validate_multiple' do
    it 'posts a JSON array body to /accounts/{id}/fields/validate-multiple' do
      values = [{ field_id: 'field-1', value: '111' }, { field_id: 'field-2', value: 'a@b.c' }]
      stub_request(:post, "#{base_url}/accounts/acc/fields/validate-multiple")
        .with(body: [{ 'field_id' => 'field-1', 'value' => '111' },
                     { 'field_id' => 'field-2', 'value' => 'a@b.c' }])
        .to_return(api_envelope([{ 'success' => false }, { 'success' => true }]))

      result = resource.validate_multiple(values)

      expect(result.size).to eq(2)
      expect(a_request(:post, "#{base_url}/accounts/acc/fields/validate-multiple")).to have_been_made
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
