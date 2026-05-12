# frozen_string_literal: true

module Assinafy
  # Top-level entry point for the Assinafy Ruby SDK.
  #
  # A Client owns a single Faraday connection (with shared auth headers,
  # timeouts, and User-Agent) and exposes one resource accessor per
  # documented API surface.
  #
  # @example Construct from positional args
  #   client = Assinafy::Client.create(ENV['ASSINAFY_API_KEY'], ENV['ASSINAFY_ACCOUNT_ID'])
  #
  # @example Construct from a config Hash (e.g. parsed YAML/JSON)
  #   client = Assinafy::Client.from_config(api_key: '...', account_id: '...')
  #
  # @see https://api.assinafy.com.br/v1/docs
  class Client
    # @return [Resources::AuthResource]
    attr_reader :auth
    # @return [Resources::DocumentResource]
    attr_reader :documents
    # @return [Resources::SignerResource]
    attr_reader :signers
    # @return [Resources::SignerDocumentResource]
    attr_reader :signer_documents
    # @return [Resources::AssignmentResource]
    attr_reader :assignments
    # @return [Resources::WebhookResource]
    attr_reader :webhooks
    # @return [Resources::TemplateResource]
    attr_reader :templates
    # @return [Resources::FieldResource]
    attr_reader :fields
    # @return [Support::WebhookVerifier]
    attr_reader :webhook_verifier

    # @param api_key        [String, nil] sent as `X-Api-Key`
    # @param token          [String, nil] legacy session token; sent as
    #   `Authorization: Bearer ...` when no `api_key` is given
    # @param account_id     [String, nil] default workspace ID for resources
    #   that need one. Each resource method also accepts an override.
    # @param base_url       [String]
    # @param webhook_secret [String, nil] secret for {Support::WebhookVerifier}
    # @param timeout        [Integer] Faraday read/open timeout in seconds
    # @param logger         [Logger, nil] receives info-level lifecycle messages
    def initialize(api_key: nil, token: nil, account_id: nil,
                   base_url: Configuration::DEFAULT_BASE_URL,
                   webhook_secret: nil,
                   timeout: Configuration::DEFAULT_TIMEOUT,
                   logger: nil)
      config = Configuration.new(
        api_key: api_key, token: token, account_id: account_id,
        base_url: base_url, webhook_secret: webhook_secret,
        timeout: timeout, logger: logger
      )

      @connection = build_connection(config)
      @logger     = config.logger || NullLogger.new

      @auth             = Resources::AuthResource.new(@connection, nil, @logger)
      @documents        = Resources::DocumentResource.new(@connection, account_id, @logger)
      @signers          = Resources::SignerResource.new(@connection, account_id, @logger)
      @signer_documents = Resources::SignerDocumentResource.new(@connection, nil, @logger)
      @assignments      = Resources::AssignmentResource.new(@connection, account_id, @logger)
      @webhooks         = Resources::WebhookResource.new(@connection, account_id, @logger)
      @templates        = Resources::TemplateResource.new(@connection, account_id, @logger)
      @fields           = Resources::FieldResource.new(@connection, account_id, @logger)
      @webhook_verifier = Support::WebhookVerifier.new(webhook_secret)
    end

    # Convenience constructor with positional `api_key`/`account_id`.
    #
    # @param api_key    [String]
    # @param account_id [String]
    # @param options    [Hash] forwarded to {#initialize}
    # @return [Client]
    def self.create(api_key, account_id, **options)
      new(api_key: api_key, account_id: account_id, **options)
    end

    # Build a Client from a Hash (string or symbol keys).
    # Useful for credentials loaded from YAML/JSON.
    #
    # @param config [Hash]
    # @return [Client]
    def self.from_config(config)
      from_hash(config)
    end

    # Alias of {.from_config} for symmetry with {Configuration.from_hash}.
    #
    # @param config [Hash]
    # @return [Client]
    def self.from_hash(config)
      cfg = Configuration.from_hash(config)
      new(
        api_key:        cfg.api_key,
        token:          cfg.token,
        account_id:     cfg.account_id,
        base_url:       cfg.base_url,
        webhook_secret: cfg.webhook_secret,
        timeout:        cfg.timeout,
        logger:         cfg.logger
      )
    end

    # High-level helper that bundles the most common workflow:
    # upload PDF → (optionally wait for metadata) → create signers → create a
    # virtual assignment for them.
    #
    # @param source         [String, Hash]   see {Resources::DocumentResource#upload}
    # @param signers        [Array<Hash>]    see {Resources::SignerResource#create}
    # @param message        [String, nil]
    # @param wait_for_ready [Boolean]        poll until the document is metadata-ready (default true)
    # @param expires_at     [String, nil]    ISO 8601 expiration for the assignment
    # @param copy_receivers [Array<String>, nil] signer IDs that only receive copies
    # @param account_id     [String, nil]    override the client default
    # @return [Hash{Symbol=>Object}] `{ document:, assignment:, signer_ids: [...] }`
    def upload_and_request_signatures(source:, signers:, message: nil,
                                      wait_for_ready: true, expires_at: nil,
                                      copy_receivers: nil, account_id: nil)
      raise ValidationError.new('At least one signer is required') if signers.nil? || signers.empty?

      @logger.info("Starting upload and signature workflow for #{signers.length} signer(s)")

      upload_opts = account_id ? { account_id: account_id } : {}
      document = @documents.upload(source, upload_opts)
      @documents.wait_until_ready(document['id']) if wait_for_ready

      signer_ids = signers.map { |signer| @signers.create(signer, account_id)['id'] }

      assignment_payload = { method: 'virtual', signers: signer_ids,
                             message: message, expires_at: expires_at,
                             copy_receivers: copy_receivers }
      assignment = @assignments.create(document['id'], assignment_payload)

      @logger.info("Upload and signature workflow completed for document #{document['id']}")

      { document: document, assignment: assignment, signer_ids: signer_ids }
    end

    # Expose the underlying Faraday connection (for advanced use cases,
    # such as adding middleware or inspecting headers in tests).
    #
    # @return [Faraday::Connection]
    def faraday_connection
      @connection
    end

    private

    def build_connection(config)
      Faraday.new(url: config.base_url) do |f|
        f.request :multipart
        f.request :json
        f.response :json, content_type: /\bjson/
        f.options.timeout = config.timeout
        f.headers.merge!(config.auth_headers)
        f.headers['Accept']       = 'application/json'
        f.headers['User-Agent']   = "assinafy-ruby-sdk/#{VERSION}"
        f.adapter Faraday.default_adapter
      end
    end
  end
end
