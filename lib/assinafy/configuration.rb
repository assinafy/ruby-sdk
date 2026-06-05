# frozen_string_literal: true

module Assinafy
  # Immutable-ish bag of SDK configuration values. Constructed implicitly by
  # {Client#initialize} or explicitly via {.from_hash} for credentials loaded
  # from YAML/JSON.
  #
  # @example Build from a YAML-style hash (e.g. loaded from config/assinafy.yml)
  #   raw = YAML.load_file('config/assinafy.yml') # => string-keyed Hash
  #   # raw => {
  #   #   "api_key"        => "hAvmvk6Urzus3byLD2qOWrg",
  #   #   "account_id"     => "a1b2c3d4-0000-1111-2222-333344445555",
  #   #   "base_url"       => "https://api.assinafy.com.br/v1",
  #   #   "webhook_secret" => "whsec_3f9a...",
  #   #   "timeout"        => 30
  #   # }
  #   config = Assinafy::Configuration.from_hash(raw)
  #   config.api_key      # => "hAvmvk6Urzus3byLD2qOWrg"
  #   config.account_id   # => "a1b2c3d4-0000-1111-2222-333344445555"
  #   config.auth_headers # => { "X-Api-Key" => "hAvmvk6Urzus3byLD2qOWrg" }
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

    # Build a configuration directly from keyword arguments. Prefer passing
    # `api_key` (the documented `X-Api-Key` mechanism); `token` is the legacy
    # bearer fallback. `base_url` has its trailing slash stripped on assignment.
    #
    # @param api_key [String, nil] sent as the `X-Api-Key` header
    # @param token [String, nil] legacy bearer token (used only when `api_key` is nil)
    # @param account_id [String, nil] default workspace account ID
    # @param base_url [String] API base URL (trailing slash is stripped)
    # @param webhook_secret [String, nil] secret for {Support::WebhookVerifier}
    # @param timeout [Integer] Faraday open/read timeout in seconds
    # @param logger [Logger, nil] optional logger for Faraday
    #
    # @example Construct with an API key (omits the default base_url)
    #   config = Assinafy::Configuration.new(
    #     api_key:    'hAvmvk6Urzus3byLD2qOWrg',
    #     account_id: 'a1b2c3d4-0000-1111-2222-333344445555'
    #   )
    #   config.base_url     # => "https://api.assinafy.com.br/v1"
    #   config.timeout      # => 30
    #   config.auth_headers # => { "X-Api-Key" => "hAvmvk6Urzus3byLD2qOWrg" }
    #
    # @example Trailing slash on base_url is stripped
    #   Assinafy::Configuration.new(base_url: 'https://api.assinafy.com.br/v1/').base_url
    #   # => "https://api.assinafy.com.br/v1"
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
    # Missing keys fall back to defaults (`base_url` => {DEFAULT_BASE_URL},
    # `timeout` => {DEFAULT_TIMEOUT}); `timeout` is coerced via `#to_i`.
    #
    # @param hash [Hash{String,Symbol=>Object}]
    # @return [Configuration]
    #
    # @example Symbol-keyed hash with the legacy access_token alias
    #   config = Assinafy::Configuration.from_hash(
    #     access_token: 'legacy-bearer-abc123',
    #     account_id:   'a1b2c3d4-0000-1111-2222-333344445555',
    #     timeout:      '45' # string is coerced via #to_i
    #   )
    #   config.token        # => "legacy-bearer-abc123"
    #   config.api_key      # => nil
    #   config.timeout      # => 45
    #   config.base_url     # => "https://api.assinafy.com.br/v1"
    #   config.auth_headers # => { "Authorization" => "Bearer legacy-bearer-abc123" }
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
    # `X-Api-Key` (the documented mechanism) over a bearer token. When `api_key`
    # is set it wins; otherwise a non-nil `token` produces an `Authorization:
    # Bearer` header; with neither credential set an empty Hash is returned.
    #
    # @return [Hash{String=>String}] one of `{ "X-Api-Key" => ... }`,
    #   `{ "Authorization" => "Bearer ..." }`, or `{}`
    #
    # @example api_key takes precedence over token
    #   Assinafy::Configuration.new(api_key: 'k', token: 't').auth_headers
    #   # => { "X-Api-Key" => "k" }
    #
    # @example Bearer fallback when only a token is present
    #   Assinafy::Configuration.new(token: 't').auth_headers
    #   # => { "Authorization" => "Bearer t" }
    #
    # @example No credentials configured
    #   Assinafy::Configuration.new.auth_headers
    #   # => {}
    def auth_headers
      return { 'X-Api-Key' => api_key } if api_key
      return { 'Authorization' => "Bearer #{token}" } if token

      {}
    end
  end
end
