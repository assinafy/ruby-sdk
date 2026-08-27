# frozen_string_literal: true

require 'uri'

require_relative 'errors'

module Assinafy
  # SDK configuration values. {Client} snapshots these values when it builds
  # its connection; construct a new client after changing a configuration.
  #
  # @example Build from a YAML-style hash (e.g. loaded from config/assinafy.yml)
  #   raw = YAML.load_file('config/assinafy.yml') # => string-keyed Hash
  #   # raw => {
  #   #   "api_key"        => "example_api_key",
  #   #   "account_id"     => "account_example",
  #   #   "base_url"       => "https://api.assinafy.com.br/v1",
  #   #   "webhook_secret" => "gateway_secret",
  #   #   "timeout"        => 30
  #   # }
  #   config = Assinafy::Configuration.from_hash(raw)
  #   config.api_key      # => "example_api_key"
  #   config.account_id   # => "account_example"
  #   config.auth_headers # => { "X-Api-Key" => "example_api_key" }
  class Configuration
    # Default base URL (production v1 API).
    DEFAULT_BASE_URL = 'https://api.assinafy.com.br/v1'
    # Default Faraday open/read timeout, in seconds.
    DEFAULT_TIMEOUT  = 30
    # Schemes accepted for {#base_url}. Credentials are attached to every request
    # sent to this host, so anything that is not absolute HTTP(S) is rejected.
    BASE_URL_SCHEMES = %w[http https].freeze

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
    #     api_key:    'example_api_key',
    #     account_id: 'account_example'
    #   )
    #   config.base_url     # => "https://api.assinafy.com.br/v1"
    #   config.timeout      # => 30
    #   config.auth_headers # => { "X-Api-Key" => "example_api_key" }
    #
    # @example Trailing slash on base_url is stripped
    #   Assinafy::Configuration.new(base_url: 'https://api.assinafy.com.br/v1/').base_url
    #   # => "https://api.assinafy.com.br/v1"
    #
    # @example A base_url that is not an absolute http(s) URL is rejected
    #   Assinafy::Configuration.new(base_url: 'api.assinafy.com.br/v1')
    #   # raises Assinafy::ValidationError ("Base URL must be an absolute http(s) URL")
    def initialize(api_key: nil, token: nil, account_id: nil,
                   base_url: DEFAULT_BASE_URL, webhook_secret: nil,
                   timeout: DEFAULT_TIMEOUT, logger: nil)
      @api_key        = api_key
      @token          = token
      @account_id     = account_id
      @base_url       = normalize_base_url(base_url)
      @webhook_secret = webhook_secret
      @timeout        = normalize_timeout(timeout)
      @logger         = logger
    end

    # Build a {Configuration} from a Hash with string or symbol keys.
    # Accepts both `'token'` and `'access_token'` for backwards compatibility.
    # Missing keys fall back to defaults (`base_url` => {DEFAULT_BASE_URL},
    # `timeout` => {DEFAULT_TIMEOUT}); numeric strings are accepted, while
    # invalid and non-positive values raise {ValidationError}.
    #
    # @param hash [Hash{String,Symbol=>Object}]
    # @return [Configuration]
    #
    # @example Symbol-keyed hash with the legacy access_token alias
    #   config = Assinafy::Configuration.from_hash(
    #     access_token: 'legacy-bearer-abc123',
    #     account_id:   'account_example',
    #     timeout:      '45'
    #   )
    #   config.token        # => "legacy-bearer-abc123"
    #   config.api_key      # => nil
    #   config.timeout      # => 45
    #   config.base_url     # => "https://api.assinafy.com.br/v1"
    #   config.auth_headers # => { "Authorization" => "Bearer legacy-bearer-abc123" }
    def self.from_hash(hash)
      raise ValidationError.new('Configuration must be a Hash') unless hash.is_a?(Hash)

      h = hash.transform_keys(&:to_s)
      new(
        api_key:        h['api_key'],
        token:          h['token'] || h['access_token'],
        account_id:     h['account_id'],
        base_url:       h.key?('base_url') ? h['base_url'] : DEFAULT_BASE_URL,
        webhook_secret: h['webhook_secret'],
        timeout:        h.key?('timeout') ? h['timeout'] : DEFAULT_TIMEOUT,
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
      key = api_key.to_s.strip
      bearer = token.to_s.strip
      return { 'X-Api-Key' => key } unless key.empty?
      return { 'Authorization' => "Bearer #{bearer}" } unless bearer.empty?

      {}
    end

    private

    # Strip the trailing slash and require an absolute http(s) URL with a host.
    # Without this the SDK would happily attach `X-Api-Key` to an `ftp:` or
    # scheme-less base, or surface a raw URI::InvalidURIError from Faraday.
    def normalize_base_url(value)
      raise ValidationError.new('Base URL is required') unless value.is_a?(String)

      url = value.strip.sub(%r{/+\z}, '')
      raise ValidationError.new('Base URL is required') if url.empty?

      uri = URI.parse(url)
      unless BASE_URL_SCHEMES.include?(uri.scheme) && !uri.host.to_s.empty?
        raise ValidationError.new('Base URL must be an absolute http(s) URL', { base_url: value })
      end

      url
    rescue URI::InvalidURIError => e
      raise ValidationError.new("Base URL is not a valid URL: #{e.message}", { base_url: value })
    end

    def normalize_timeout(value)
      raw = value.nil? ? DEFAULT_TIMEOUT : value
      seconds = Integer(raw, exception: false) if raw.is_a?(Integer) || raw.is_a?(String)
      return seconds if seconds&.positive?

      raise ValidationError.new('Timeout must be a positive integer')
    end
  end
end
