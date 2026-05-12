# frozen_string_literal: true

module Assinafy
  # Immutable-ish bag of SDK configuration values. Constructed implicitly by
  # {Client#initialize} or explicitly via {.from_hash} for credentials loaded
  # from YAML/JSON.
  class Configuration
    # Default base URL (production v1 API).
    DEFAULT_BASE_URL = 'https://api.assinafy.com.br/v1'
    # Default Faraday open/read timeout, in seconds.
    DEFAULT_TIMEOUT  = 30

    # @!attribute [rw] api_key
    #   @return [String, nil] sent as `X-Api-Key`
    # @!attribute [rw] token
    #   @return [String, nil] legacy bearer token (used when `api_key` is nil)
    # @!attribute [rw] account_id
    #   @return [String, nil] default workspace ID
    # @!attribute [rw] base_url
    #   @return [String] API base URL (trailing slash stripped)
    # @!attribute [rw] webhook_secret
    #   @return [String, nil] secret for {Support::WebhookVerifier}
    # @!attribute [rw] timeout
    #   @return [Integer] Faraday timeout in seconds
    # @!attribute [rw] logger
    #   @return [Logger, nil]
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

    # Build a {Configuration} from a Hash with string or symbol keys.
    # Accepts both `'token'` and `'access_token'` for backwards compatibility.
    #
    # @param hash [Hash]
    # @return [Configuration]
    def self.from_hash(hash)
      h = hash.transform_keys(&:to_s)
      new(
        api_key:        h['api_key'],
        token:          h['token'] || h['access_token'],
        account_id:     h['account_id'],
        base_url:       h['base_url'] || DEFAULT_BASE_URL,
        webhook_secret: h['webhook_secret'],
        timeout:        h['timeout'] ? h['timeout'].to_i : DEFAULT_TIMEOUT,
        logger:         h['logger']
      )
    end

    # Return the HTTP headers used to authenticate requests, preferring
    # `X-Api-Key` (the documented mechanism) over a bearer token.
    #
    # @return [Hash{String=>String}]
    def auth_headers
      return { 'X-Api-Key' => api_key } if api_key
      return { 'Authorization' => "Bearer #{token}" } if token

      {}
    end
  end
end
