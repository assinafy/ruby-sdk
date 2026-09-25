# frozen_string_literal: true

require_relative '../scripts/check_api_contract'

RSpec.describe AssinafyApiContract do
  # The coverage matrix stores paths relative to the `/v1` base URL, while the
  # upstream contract spells them in full. `/.well-known/*` is the exception:
  # RFC 8615 puts it at the host root, outside the version prefix.
  let(:normalize_operation) do
    lambda do |method, path|
      versioned_path = path.start_with?('/v1/', '/.well-known/') ? path : "/v1#{path}"
      "#{method} #{versioned_path.gsub(/\{[^}]+\}/, '{}')}"
    end
  end

  describe '.fetch_remote' do
    it 'uses the SDK User-Agent for the Assinafy contract request' do
      stub_request(:get, described_class::SOURCE.to_s)
        .with(headers: { 'User-Agent' => Assinafy::USER_AGENT })
        .to_return(status: 200, body: '{}')

      expect(described_class.fetch_remote).to eq('{}')
    end

    it 'requires TLS 1.2 or newer' do
      stub_request(:get, described_class::SOURCE.to_s).to_return(status: 200, body: '{}')
      allow(Net::HTTP).to receive(:start).and_call_original

      described_class.fetch_remote

      expect(Net::HTTP).to have_received(:start)
        .with(anything, anything, hash_including(min_version: OpenSSL::SSL::TLS1_2_VERSION))
    end
  end

  describe 'the SDK route matrix' do
    it 'contains every expected upstream operation plus the five template operations' do
      expected = JSON.parse(File.binread(described_class::EXPECTED_PATH)).fetch('operations').map do |operation|
        method, path = operation.split(' ', 2)
        normalize_operation.call(method, path)
      end

      matrix_source = File.binread(File.expand_path('api_coverage_spec.rb', __dir__))
      mapped = matrix_source.scan(/\['(GET|POST|PUT|PATCH|DELETE)',\s+'([^']+)',\s+'[^']+'\]/m).map do |method, path|
        normalize_operation.call(method, path)
      end

      extensions = [
        'GET /v1/accounts/{}/templates/{}',
        'POST /v1/accounts/{}/templates',
        'PUT /v1/accounts/{}/templates/{}',
        'DELETE /v1/accounts/{}/templates/{}',
        'GET /v1/accounts/{}/templates/{}/pages/{}/download'
      ]

      expect(mapped & expected).to match_array(expected)
      expect(mapped - expected).to match_array(extensions)
    end
  end
end
