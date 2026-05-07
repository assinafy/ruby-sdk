# frozen_string_literal: true

module Assinafy
  class Configuration
    DEFAULT_BASE_URL = 'https://api.assinafy.com.br/v1'
    DEFAULT_TIMEOUT  = 30

    attr_accessor :api_key, :token, :account_id, :base_url, :webhook_secret, :timeout, :logger

    def initialize(api_key: nil, token: nil, account_id: nil,
                   base_url: DEFAULT_BASE_URL, webhook_secret: nil,
                   timeout: DEFAULT_TIMEOUT, logger: nil)
      @api_key        = api_key
      @token          = token
      @account_id     = account_id
      @base_url       = base_url.to_s.chomp('/')
      @webhook_secret = webhook_secret
      @timeout        = timeout || DEFAULT_TIMEOUT
      @logger         = logger
    end

    def self.from_hash(hash)
      h = hash.transform_keys { |k| k.to_s }
      new(
        api_key:        h['api_key'],
        token:          h['token'] || h['access_token'],
        account_id:     h['account_id'],
        base_url:       h['base_url'] || DEFAULT_BASE_URL,
        webhook_secret: h['webhook_secret'],
        timeout:        h['timeout'] || DEFAULT_TIMEOUT,
        logger:         h['logger']
      )
    end

    def auth_headers
      return { 'X-Api-Key' => api_key } if api_key
      return { 'Authorization' => "Bearer #{token}" } if token
      {}
    end
  end
end
