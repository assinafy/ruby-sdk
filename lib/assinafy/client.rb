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
    # @return [Resources::AccountResource]
    attr_reader :accounts
    # @return [Resources::UserResource]
    attr_reader :users
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
    # @return [Resources::TagResource]
    attr_reader :tags
    # @return [Support::WebhookVerifier]
    attr_reader :webhook_verifier

    # @param api_key        [String, nil] sent as `X-Api-Key`
    # @param token          [String, nil] legacy session token; sent as
    #   `Authorization: Bearer ...` when no `api_key` is given
    # @param account_id     [String, nil] default workspace ID for account-scoped
    #   resources; those methods document their supported per-call overrides
    # @param base_url       [String]
    # @param webhook_secret [String, nil] secret for {Support::WebhookVerifier}
    # @param timeout        [Integer] Faraday read/open timeout in seconds
    # @param logger         [Logger, nil] receives info-level lifecycle messages
    #
    # @example Build a client and reach a resource accessor (no network call)
    #   client = Assinafy::Client.new(api_key: 'example_api_key', account_id: 'account_example')
    #   client.documents #=> #<Assinafy::Resources::DocumentResource ...>
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
      @accounts         = Resources::AccountResource.new(@connection, account_id, @logger)
      @users            = Resources::UserResource.new(@connection, nil, @logger)
      @documents        = Resources::DocumentResource.new(@connection, account_id, @logger)
      @signers          = Resources::SignerResource.new(@connection, account_id, @logger)
      @signer_documents = Resources::SignerDocumentResource.new(@connection, nil, @logger)
      @assignments      = Resources::AssignmentResource.new(@connection, account_id, @logger)
      @webhooks         = Resources::WebhookResource.new(@connection, account_id, @logger)
      @templates        = Resources::TemplateResource.new(@connection, account_id, @logger)
      @fields           = Resources::FieldResource.new(@connection, account_id, @logger)
      @tags             = Resources::TagResource.new(@connection, account_id, @logger)
      @webhook_verifier = Support::WebhookVerifier.new(webhook_secret)
    end

    # Convenience constructor with positional `api_key`/`account_id`.
    #
    # @param api_key    [String]
    # @param account_id [String]
    # @param options    [Hash] forwarded to {#initialize}
    # @return [Client]
    #
    # @example Construct with positional credentials and an optional webhook secret
    #   client = Assinafy::Client.create('example_api_key', 'account_example', webhook_secret: 'gateway_secret')
    #   client #=> #<Assinafy::Client ...>
    def self.create(api_key, account_id, **options)
      new(api_key: api_key, account_id: account_id, **options)
    end

    # Build a Client from a Hash (string or symbol keys).
    # Useful for credentials loaded from YAML/JSON.
    #
    # @param config [Hash]
    # @return [Client]
    #
    # @example Build from a credentials Hash loaded from YAML/JSON (string or symbol keys both work)
    #   creds  = YAML.load_file('config/assinafy.yml') # { 'api_key' => '...', 'account_id' => '...' }
    #   client = Assinafy::Client.from_config(creds)
    #   client #=> #<Assinafy::Client ...>
    def self.from_config(config)
      from_hash(config)
    end

    # Alias of {.from_config} for symmetry with {Configuration.from_hash}.
    #
    # @param config [Hash]
    # @return [Client]
    #
    # @example Build from a symbol-keyed Hash
    #   client = Assinafy::Client.from_hash(api_key: 'example_api_key', account_id: 'account_example')
    #   client #=> #<Assinafy::Client ...>
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
    # @return [Hash{Symbol=>Object}] `{ document: {Hash}, assignment: {Hash}, signer_ids: [String, ...] }`
    #   where `document` is the (unwrapped) document payload, `assignment` is the (unwrapped) virtual
    #   assignment, and `signer_ids` lists the IDs of the signers created during the workflow.
    # @note This helper is not transactional. If a later API call fails, an uploaded
    #   document or newly created signer may remain and should be cleaned up by the caller.
    #   After an upload succeeds, SDK errors include the latest `document` and the
    #   successfully created `signer_ids` in {Error#context} for recovery.
    #
    # @example Upload a PDF and request a virtual signature from one signer
    #   result = client.upload_and_request_signatures(
    #     source:  '/path/to/contract.pdf',
    #     signers: [{ full_name: 'Example Signer', email: 'signer@example.com' }],
    #     message: 'Please review and sign'
    #   )
    #
    #   # Under the hood the SDK uploads the file, then POSTs this JSON body to
    #   # POST /documents/{document_id}/assignments (nil optional fields are dropped):
    #   #   {
    #   #     "method": "virtual",
    #   #     "signers": [{ "id": "19e6b92e7895332ed9708535d8c" }],
    #   #     "message": "Please review and sign"
    #   #   }
    #
    #   # Returned (unwrapped) Hash:
    #   result
    #   #=> {
    #   #     document: {
    #   #       "resource" => "document", "id" => "1032009d72b364f377ff270405cc",
    #   #       "account_id" => "account_example", "name" => "contract.pdf",
    #   #       "status" => "metadata_ready",
    #   #       "artifacts" => { "original" => "https://.../download/original", "thumbnail" => "https://..." },
    #   #       "tags" => [], "pages" => [{ "id" => "...", "number" => 1, "height" => 1651, "width" => 1275 }]
    #   #       # ... (see docs for full shape)
    #   #     },
    #   #     assignment: {
    #   #       "resource" => "assignment", "id" => "19e99aa0633e32ac13f845c08db",
    #   #       "sender_email" => "sender@example.com", "method" => "virtual",
    #   #       "expires_at" => nil, "message" => "Please review and sign",
    #   #       "signers" => [{ "id" => "19e6b92e7895332ed9708535d8c", "full_name" => "Example Signer",
    #   #                       "email" => "signer@example.com", "completed" => false, "step" => 1 }],
    #   #       "copy_receivers" => [], "items" => [{ "id" => "103200a43e372db16f48a6f0f2d4", "completed" => false }],
    #   #       "summary" => { "signer_count" => 1, "completed_count" => 0 },
    #   #       "signing_urls" => [{ "signer_id" => "19e6b92e7895332ed9708535d8c", "url" => "https://.../sign/..." }]
    #   #       # ... (see docs for full shape)
    #   #     },
    #   #     signer_ids: ["19e6b92e7895332ed9708535d8c"]
    #   #   }
    def upload_and_request_signatures(source:, signers:, message: nil,
                                      wait_for_ready: true, expires_at: nil,
                                      copy_receivers: nil, account_id: nil)
      validate_signature_workflow!(signers, wait_for_ready)

      @logger.info("Starting upload and signature workflow for #{signers.length} signer(s)")

      upload_opts = account_id.nil? ? {} : { account_id: account_id }
      document = @documents.upload(source, upload_opts)
      signer_ids = []

      begin
        document = @documents.wait_until_ready(document['id']) if wait_for_ready
        signers.each do |signer|
          signer_ids << signer_id!(@signers.create(signer, account_id))
        end

        assignment_payload = { method: 'virtual', signers: signer_ids,
                               message: message, expires_at: expires_at,
                               copy_receivers: copy_receivers }
        assignment = @assignments.create(document['id'], assignment_payload)
        created_resource_id!(assignment, 'Assignment')

        @logger.info("Upload and signature workflow completed for document #{document['id']}")

        { document: document, assignment: assignment, signer_ids: signer_ids }
      rescue Error => e
        e.context[:document] ||= document
        e.context[:signer_ids] = signer_ids.dup
        raise
      end
    end

    # Expose the underlying Faraday connection (for advanced use cases,
    # such as adding middleware or inspecting headers in tests).
    #
    # @return [Faraday::Connection]
    #
    # @example Inspect the auth header the SDK sends
    #   client = Assinafy::Client.new(api_key: 'example_api_key', account_id: 'account_example')
    #   client.faraday_connection.headers['X-Api-Key'] #=> "example_api_key"
    def faraday_connection
      @connection
    end

    private

    def build_connection(config)
      Faraday.new(url: config.base_url) do |f|
        f.request :multipart
        f.request :json
        f.response :json, content_type: /\bjson/
        f.options.timeout      = config.timeout
        f.options.open_timeout = config.timeout
        f.headers.merge!(config.auth_headers)
        f.headers['Accept']       = 'application/json'
        f.headers['User-Agent']   = USER_AGENT
        f.adapter Faraday.default_adapter
      end
    end

    def validate_signature_workflow!(signers, wait_for_ready)
      unless signers.is_a?(Array) && !signers.empty? && signers.all?(Hash)
        raise ValidationError.new('Signers must be a non-empty Array of Hashes')
      end
      unless [true, false].include?(wait_for_ready)
        raise ValidationError.new('wait_for_ready must be true or false')
      end

      signers.each { |signer| @signers.validate_create!(signer) }
    end

    def signer_id!(response)
      created_resource_id!(response, 'Signer')
    end

    def created_resource_id!(response, resource_name)
      id = response['id'] if response.is_a?(Hash)
      return id if id.is_a?(String) && Resources::BaseResource::PATH_SEGMENT.match?(id) && !%w[. ..].include?(id)

      raise Error.new(
        "#{resource_name} created but the API returned no usable ID",
        { response_data: response }
      )
    end
  end
end
