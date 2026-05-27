# frozen_string_literal: true

RSpec.describe Assinafy::Resources::TagResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }
  let(:resource)   { described_class.new(connection, 'acc') }

  describe '#list' do
    it 'calls GET /accounts/{id}/tags with search params' do
      stub_request(:get, "#{base_url}/accounts/acc/tags")
        .with(query: hash_including('search' => 'contract'))
        .to_return(api_envelope([{ 'id' => 'tag-1', 'name' => 'Contracts' }]))

      result = resource.list(search: 'contract')

      expect(result[:data].first['id']).to eq('tag-1')
    end
  end

  describe '#create' do
    it 'posts a tag payload' do
      stub_request(:post, "#{base_url}/accounts/acc/tags")
        .to_return(api_envelope({ 'id' => 'tag-1', 'name' => 'Contracts' }))

      result = resource.create(name: 'Contracts', color: 'ff8800')

      expect(result['id']).to eq('tag-1')
      expect(
        a_request(:post, "#{base_url}/accounts/acc/tags")
          .with(body: hash_including('name' => 'Contracts', 'color' => 'ff8800'))
      ).to have_been_made
    end

    it 'requires a tag name' do
      expect { resource.create(color: 'ff8800') }.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#update' do
    it 'puts to /accounts/{id}/tags/{tag_id}' do
      stub_request(:put, "#{base_url}/accounts/acc/tags/tag-1")
        .to_return(api_envelope({ 'id' => 'tag-1', 'name' => 'Sales Contracts' }))

      result = resource.update('tag-1', name: 'Sales Contracts')

      expect(result['name']).to eq('Sales Contracts')
      expect(a_request(:put, "#{base_url}/accounts/acc/tags/tag-1")).to have_been_made
    end

    it 'preserves nil color so callers can clear it' do
      stub_request(:put, "#{base_url}/accounts/acc/tags/tag-1")
        .to_return(api_envelope({ 'id' => 'tag-1', 'color' => nil }))

      resource.update('tag-1', color: nil)

      expect(
        a_request(:put, "#{base_url}/accounts/acc/tags/tag-1")
          .with(body: { 'color' => nil })
      ).to have_been_made
    end
  end

  describe '#delete' do
    it 'deletes a tag without force by default' do
      stub_request(:delete, "#{base_url}/accounts/acc/tags/tag-1")
        .to_return(api_envelope({ 'deleted' => true }))

      expect(resource.delete('tag-1')['deleted']).to be true
    end

    it 'passes force as a query parameter when requested' do
      stub_request(:delete, "#{base_url}/accounts/acc/tags/tag-1")
        .with(query: hash_including('force' => 'true'))
        .to_return(api_envelope({ 'deleted' => true }))

      resource.delete('tag-1', force: true)

      expect(
        a_request(:delete, "#{base_url}/accounts/acc/tags/tag-1")
          .with(query: hash_including('force' => 'true'))
      ).to have_been_made
    end
  end
end
