# frozen_string_literal: true

RSpec.describe Assinafy::Resources::BaseResource do
  subject(:resource) { resource_class.new(connection) }

  let(:base_url) { 'https://api.assinafy.com.br/v1' }
  let(:connection) do
    build_test_connection(base_url).tap do |conn|
      conn.headers['Authorization'] = 'Bearer test-token'
    end
  end
  let(:resource_class) do
    Class.new(described_class) do
      def list
        call_list('List failed') { http_get('items') }
      end

      def array
        call_array('Array failed') { http_get('array') }
      end

      def binary
        call_binary('Download failed') { http_get('binary') }
      end

      def public_request
        call('Public request failed') { http_get('public', workspace_auth: false) }
      end

      def source(value)
        read_source(value)
      end

      def pdf(value)
        buffer, file_name = read_source(value)
        validate_pdf_source!(buffer, file_name)
      end

      def default_account
        account_id
      end
    end
  end

  describe 'response shape enforcement' do
    it 'accepts raw, nested, and enveloped Array list payloads' do
      responses = [
        json_response([{ 'id' => 1 }]),
        json_response({ 'data' => [{ 'id' => 2 }] }),
        api_envelope([{ 'id' => 3 }])
      ]
      stub_request(:get, "#{base_url}/items").to_return(*responses)

      expect([resource.list, resource.list, resource.list].map { |result| result[:data].first['id'] })
        .to eq([1, 2, 3])
    end

    it 'rejects malformed list payloads instead of treating them as empty' do
      [nil, 'not-a-list', { 'unexpected' => [] }].each do |body|
        stub_request(:get, "#{base_url}/items").to_return(json_response(body))

        expect { resource.list }.to raise_error(Assinafy::Error, /Array list payload/)
      end
    end

    it 'accepts only Array payloads for non-paginated collections' do
      stub_request(:get, "#{base_url}/array").to_return(api_envelope([{ 'id' => 1 }]))
      expect(resource.array).to eq([{ 'id' => 1 }])

      stub_request(:get, "#{base_url}/array").to_return(api_envelope({ 'id' => 1 }))
      expect { resource.array }.to raise_error(Assinafy::Error, /Array data payload/)
    end

    it 'accepts non-empty binary responses' do
      stub_request(:get, "#{base_url}/binary")
        .to_return(status: 200, body: '%PDF-1.7', headers: { 'Content-Type' => 'application/pdf' })

      expect(resource.binary).to eq('%PDF-1.7'.b)
      expect(resource.binary.encoding).to eq(Encoding::BINARY)
    end

    it 'rejects empty and textual success responses from binary endpoints' do
      responses = [
        { status: 200, body: '', headers: { 'Content-Type' => 'application/pdf' } },
        { status: 200, body: '<html>error</html>', headers: { 'Content-Type' => 'text/html' } },
        json_response({ 'status' => 200, 'data' => nil })
      ]
      stub_request(:get, "#{base_url}/binary").to_return(*responses)

      3.times do
        expect { resource.binary }.to raise_error(Assinafy::Error, /non-empty binary body/)
      end
    end
  end

  describe 'request authentication' do
    it 'sets the exact versioned SDK User-Agent on directly constructed resources' do
      connection.headers['User-Agent'] = 'custom-agent'

      resource

      expect(connection.headers['User-Agent']).to eq('Assinafy-Ruby-SDK/v1.5.1')
      expect(connection.headers['User-Agent']).to eq(Assinafy::USER_AGENT)
    end

    it 'restores the SDK User-Agent before every resource request' do
      stub_request(:get, "#{base_url}/array")
        .with(headers: { 'User-Agent' => Assinafy::USER_AGENT })
        .to_return(api_envelope([]))
      resource
      connection.headers['User-Agent'] = 'custom-agent'

      expect(resource.array).to eq([])
    end

    it 'removes inherited workspace credentials from public requests' do
      request = stub_request(:get, "#{base_url}/public")
                .with { |req| !req.headers.key?('X-Api-Key') && !req.headers.key?('Authorization') }
                .to_return(api_envelope({ 'ok' => true }))

      expect(resource.public_request['ok']).to be true
      expect(request).to have_been_requested
    end
  end

  describe 'configuration snapshots' do
    it 'does not retain a caller-mutable account ID String' do
      account = String.new('account-original')
      configured = resource_class.new(connection, account)
      account.replace('account-changed')

      expect(configured.default_account).to eq('account-original')
    end
  end

  describe 'upload source validation' do
    it 'accepts String PDF bytes with a safe file name' do
      expect(resource.pdf(buffer: "prefix\n%PDF-1.7\n", file_name: 'contract.pdf')).to be_nil
    end

    it 'rejects non-String and empty buffers' do
      expect { resource.source(buffer: 123, file_name: 'file.pdf') }
        .to raise_error(Assinafy::ValidationError, /String/)
      expect { resource.source(buffer: '', file_name: 'file.pdf') }
        .to raise_error(Assinafy::ValidationError, /empty/)
    end

    it 'rejects blank, path-like, and control-character file names' do
      ['', '../file.pdf', "file\r\n.pdf"].each do |file_name|
        expect { resource.source(buffer: 'bytes', file_name: file_name) }
          .to raise_error(Assinafy::ValidationError)
      end
    end

    it 'rejects non-PDF content even when the extension is pdf' do
      expect { resource.pdf(buffer: 'plain text', file_name: 'file.pdf') }
        .to raise_error(Assinafy::ValidationError, /content is not a PDF/)
    end
  end
end
