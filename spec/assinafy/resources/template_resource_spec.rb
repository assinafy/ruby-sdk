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
    it 'uploads the source file as multipart/form-data' do
      stub_request(:post, "#{base_url}/accounts/acc/templates")
        .to_return(api_envelope({ 'id' => 'tmpl-1', 'status' => 'Uploaded' }))

      result = resource.create(buffer: '%PDF-1.4 fake', file_name: 'contract.pdf')

      expect(result['id']).to eq('tmpl-1')
      expect(
        a_request(:post, "#{base_url}/accounts/acc/templates")
          .with(headers: { 'Content-Type' => %r{\Amultipart/form-data} })
      ).to have_been_made
    end

    it 'raises when the source is not a file' do
      expect { resource.create(name: 'Template') }.to raise_error(Assinafy::ValidationError)
    end

    it 'rejects a renamed non-PDF before requesting' do
      expect do
        resource.create(buffer: 'plain text', file_name: 'contract.pdf')
      end.to raise_error(Assinafy::ValidationError, /content is not a PDF/)
      expect(a_request(:post, %r{/templates})).not_to have_been_made
    end

    it 'rejects non-String buffers and invalid options before requesting' do
      expect do
        resource.create(buffer: 123, file_name: 'contract.pdf')
      end.to raise_error(Assinafy::ValidationError, /String/)
      expect do
        resource.create({ buffer: '%PDF-1.4', file_name: 'contract.pdf' }, [])
      end.to raise_error(Assinafy::ValidationError, /Hash/)
      expect(a_request(:post, %r{/templates})).not_to have_been_made
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

  describe '#delete' do
    it 'calls DELETE /accounts/{id}/templates/{id} and returns nil' do
      stub_request(:delete, "#{base_url}/accounts/acc/templates/tmpl-1")
        .to_return(api_envelope({}))

      expect(resource.delete('tmpl-1')).to be_nil
      expect(a_request(:delete, "#{base_url}/accounts/acc/templates/tmpl-1")).to have_been_made
    end

    it 'raises ApiError on a 404 envelope' do
      stub_request(:delete, "#{base_url}/accounts/acc/templates/missing")
        .to_return(json_response({ status: 404, message: 'Template não encontrado.' }, status: 404))

      expect { resource.delete('missing') }.to raise_error(Assinafy::ApiError)
      expect(a_request(:delete, "#{base_url}/accounts/acc/templates/missing")).to have_been_made
    end
  end

  describe '#download_page' do
    it 'calls the page download endpoint and returns binary bytes' do
      stub_request(:get, "#{base_url}/accounts/acc/templates/tmpl-1/pages/page-1/download")
        .to_return(status: 200, body: 'PNGBYTES', headers: { 'Content-Type' => 'image/png' })

      result = resource.download_page('tmpl-1', 'page-1')

      expect(result).to eq('PNGBYTES')
      expect(
        a_request(:get, "#{base_url}/accounts/acc/templates/tmpl-1/pages/page-1/download")
      ).to have_been_made
    end
  end
end
