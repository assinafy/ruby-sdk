# frozen_string_literal: true

RSpec.describe Assinafy::Resources::TemplateResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }
  let(:resource)   { described_class.new(connection, 'acc') }

  describe '#list' do
    it 'calls GET /accounts/{id}/templates and returns list data' do
      stub_request(:get, "#{base_url}/accounts/acc/templates")
        .to_return(api_envelope([{ 'id' => 'tmpl-1', 'name' => 'Contract' }]))

      result = resource.list
      expect(result[:data].first['id']).to eq('tmpl-1')
    end

    it 'uses custom account_id when provided' do
      stub_request(:get, "#{base_url}/accounts/other/templates").to_return(api_envelope([]))

      resource.list({}, 'other')
      expect(a_request(:get, "#{base_url}/accounts/other/templates")).to have_been_made
    end
  end

  describe '#get' do
    it 'raises when template ID is empty' do
      expect { resource.get('') }.to raise_error(Assinafy::ValidationError)
    end

    it 'fetches template details by ID' do
      stub_request(:get, "#{base_url}/accounts/acc/templates/tmpl-1")
        .to_return(api_envelope({ 'id' => 'tmpl-1', 'name' => 'Contract' }))

      result = resource.get('tmpl-1')
      expect(result['id']).to eq('tmpl-1')
    end
  end

  describe '#create' do
    it 'posts to the account templates endpoint' do
      stub_request(:post, "#{base_url}/accounts/acc/templates")
        .to_return(api_envelope({ 'id' => 'tmpl-1' }))

      result = resource.create(name: 'Template')

      expect(result['id']).to eq('tmpl-1')
      expect(a_request(:post, "#{base_url}/accounts/acc/templates")).to have_been_made
    end
  end

  describe '#update' do
    it 'puts to the account template endpoint' do
      stub_request(:put, "#{base_url}/accounts/acc/templates/tmpl-1")
        .to_return(api_envelope({ 'id' => 'tmpl-1' }))

      result = resource.update('tmpl-1', name: 'Renamed')

      expect(result['id']).to eq('tmpl-1')
      expect(a_request(:put, "#{base_url}/accounts/acc/templates/tmpl-1")).to have_been_made
    end
  end
end
