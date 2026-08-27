# frozen_string_literal: true

RSpec.describe Assinafy::Resources::FieldResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }
  let(:resource)   { described_class.new(connection, 'acc') }

  def without_workspace_auth?(request)
    !request.headers.key?('X-Api-Key') && !request.headers.key?('Authorization')
  end

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

    it 'preserves an explicit nil regex so callers can clear it' do
      stub_request(:put, "#{base_url}/accounts/acc/fields/field-1")
        .with(body: hash_including('regex' => nil))
        .to_return(api_envelope({ 'id' => 'field-1', 'regex' => nil }))

      resource.update('field-1', regex: nil)

      expect(
        a_request(:put, "#{base_url}/accounts/acc/fields/field-1").with(body: hash_including('regex' => nil))
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
        .with(headers: { 'X-Api-Key' => 'test-key' })
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
        .with(query: hash_including('signer-access-code' => 'code')) do |request|
          without_workspace_auth?(request)
        end
        .to_return(api_envelope({ 'success' => true }))

      result = resource.validate('field-1', 'value', signer_access_code: 'code')

      expect(result['success']).to be true
      expect(a_request(:post, "#{base_url}/accounts/acc/fields/field-1/validate")
        .with(query: hash_including('signer-access-code' => 'code'))).to have_been_made
    end

    it 'rejects a blank signer access code before making a request' do
      expect { resource.validate('field-1', 'value', signer_access_code: ' ') }
        .to raise_error(Assinafy::ValidationError, /Signer access code/)
      expect(a_request(:post, "#{base_url}/accounts/acc/fields/field-1/validate")).not_to have_been_made
    end

    it 'rejects a nil value before making a request' do
      expect { resource.validate('field-1', nil) }
        .to raise_error(Assinafy::ValidationError, /Field value/)
      expect(a_request(:post, "#{base_url}/accounts/acc/fields/field-1/validate")).not_to have_been_made
    end
  end

  describe '#validate_multiple' do
    it 'posts a JSON array body to /accounts/{id}/fields/validate-multiple' do
      values = [{ field_id: 'field-1', value: '111' }, { field_id: 'field-2', value: 'a@b.c' }]
      stub_request(:post, "#{base_url}/accounts/acc/fields/validate-multiple")
        .with(body:    [{ 'field_id' => 'field-1', 'value' => '111' },
                        { 'field_id' => 'field-2', 'value' => 'a@b.c' }],
              headers: { 'X-Api-Key' => 'test-key' })
        .to_return(api_envelope([{ 'success' => false }, { 'success' => true }]))

      result = resource.validate_multiple(values)

      expect(result.size).to eq(2)
      expect(a_request(:post, "#{base_url}/accounts/acc/fields/validate-multiple")).to have_been_made
    end

    it 'uses signer-only auth when a code is supplied' do
      path = "#{base_url}/accounts/acc/fields/validate-multiple"
      stub_request(:post, path)
        .with(query: hash_including('signer-access-code' => 'code')) do |request|
          without_workspace_auth?(request)
        end
        .to_return(api_envelope([{ 'success' => true }]))

      expect(resource.validate_multiple([{ field_id: 'field-1', value: '1' }], signer_access_code: 'code'))
        .to eq([{ 'success' => true }])
    end

    it 'rejects non-Hash elements and blank codes before making a request' do
      path = "#{base_url}/accounts/acc/fields/validate-multiple"

      expect { resource.validate_multiple([{ field_id: 'field-1' }, 'bad']) }
        .to raise_error(Assinafy::ValidationError, /Field value/)
      expect { resource.validate_multiple([{ field_id: 'field-1' }], signer_access_code: '') }
        .to raise_error(Assinafy::ValidationError, /Signer access code/)
      expect(a_request(:post, path)).not_to have_been_made
    end

    it 'requires a safe String field_id and a present value in every item' do
      path = "#{base_url}/accounts/acc/fields/validate-multiple"

      [{ value: '1' }, { field_id: 2, value: '1' }, { field_id: '../bad', value: '1' },
       { field_id: 'field-1' }, { field_id: 'field-1', value: nil }].each do |item|
        expect { resource.validate_multiple([item]) }.to raise_error(Assinafy::ValidationError)
      end
      expect(a_request(:post, path)).not_to have_been_made
    end

    it 'preserves false and numeric field values' do
      path = "#{base_url}/accounts/acc/fields/validate-multiple"
      stub_request(:post, path)
        .with(body: [{ 'field_id' => 'field-1', 'value' => false },
                     { 'field_id' => 'field-2', 'value' => 0 }])
        .to_return(api_envelope([{ 'success' => true }, { 'success' => true }]))

      result = resource.validate_multiple([{ field_id: 'field-1', value: false },
                                           { field_id: 'field-2', value: 0 }])
      expect(result.size).to eq(2)
    end

    it 'rejects a malformed non-Array response' do
      path = "#{base_url}/accounts/acc/fields/validate-multiple"
      stub_request(:post, path).to_return(api_envelope({ 'success' => true }))

      expect { resource.validate_multiple([{ field_id: 'field-1', value: '1' }]) }
        .to raise_error(Assinafy::Error, /Array data payload/)
    end
  end

  describe '#types' do
    it 'calls /field-types' do
      stub_request(:get, "#{base_url}/field-types").to_return(api_envelope([]))

      resource.types

      expect(a_request(:get, "#{base_url}/field-types")).to have_been_made
    end

    it 'rejects a malformed non-Array response' do
      stub_request(:get, "#{base_url}/field-types").to_return(api_envelope({ 'type' => 'text' }))

      expect { resource.types }.to raise_error(Assinafy::Error, /Array data payload/)
    end
  end
end
