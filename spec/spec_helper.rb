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

  # `:live` specs hit the real sandbox API; everything else is fully mocked.
  # Live specs are skipped unless ASSINAFY_LIVE=1, so the default suite stays
  # fast, hermetic, and offline (as CI runs it).
  config.filter_run_excluding :live unless ENV['ASSINAFY_LIVE'] == '1'

  config.before do |example|
    if example.metadata[:live]
      WebMock.allow_net_connect!
    else
      WebMock.reset!
      WebMock.disable_net_connect!
    end
  end
end

# Mirror the middleware stack the real Client builds (see Client#build_connection),
# so multipart uploads and JSON bodies behave in specs exactly as in production.
def build_test_connection(base_url = 'https://api.assinafy.com.br/v1', api_key = 'test-key')
  Faraday.new(url: base_url) do |f|
    f.request  :multipart
    f.request  :json
    f.response :json, content_type: /\bjson/
    f.headers['X-Api-Key'] = api_key
    f.headers['Accept']    = 'application/json'
    f.headers['User-Agent'] = Assinafy::USER_AGENT
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
