# frozen_string_literal: true

module Assinafy
  class Client
    attr_reader :auth, :documents, :signers, :signer_documents, :assignments,
                :webhooks, :templates, :fields, :webhook_verifier

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

    def self.create(api_key, account_id, **options)
      new(api_key: api_key, account_id: account_id, **options)
    end

    def self.from_config(config)
      from_hash(config)
    end

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
