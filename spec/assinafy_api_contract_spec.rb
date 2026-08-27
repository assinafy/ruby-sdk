# frozen_string_literal: true

require_relative '../scripts/check_api_contract'

RSpec.describe AssinafyApiContract do
  let(:normalize_operation) do
    lambda do |method, path|
      versioned_path = path.start_with?('/v1/') ? path : "/v1#{path}"
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
