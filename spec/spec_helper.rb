# frozen_string_literal: true

require 'webmock/rspec'
require 'assinafy'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random

  config.before do
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end

def build_test_connection(base_url = 'https://api.assinafy.com.br/v1', api_key = 'test-key')
  Faraday.new(url: base_url) do |f|
    f.request  :json
    f.response :json, content_type: /\bjson/
    f.headers['X-Api-Key']     = api_key
    f.headers['Content-Type']  = 'application/json'
    f.headers['Accept']        = 'application/json'
    f.adapter :net_http
  end
end

def json_response(data, status: 200, headers: {})
  {
    status:  status,
    body:    data.to_json,
    headers: { 'Content-Type' => 'application/json' }.merge(headers)
  }
end

def api_envelope(data, status: 200)
  json_response({ status: status, data: data })
end
