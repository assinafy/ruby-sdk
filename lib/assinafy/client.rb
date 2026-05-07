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

      @auth            = Resources::AuthResource.new(@connection, nil, @logger)
      @documents       = Resources::DocumentResource.new(@connection, account_id, @logger)
      @signers         = Resources::SignerResource.new(@connection, account_id, @logger)
      @signer_documents = Resources::SignerDocumentResource.new(@connection, nil, @logger)
      @assignments     = Resources::AssignmentResource.new(@connection, account_id, @logger)
      @webhooks        = Resources::WebhookResource.new(@connection, account_id, @logger)
      @templates       = Resources::TemplateResource.new(@connection, account_id, @logger)
      @fields          = Resources::FieldResource.new(@connection, account_id, @logger)
      @webhook_verifier = Support::WebhookVerifier.new(webhook_secret)
    end

    def self.create(api_key, account_id, **options)
      new(api_key: api_key, account_id: account_id, **options)
    end

    def self.from_config(config)
      h = config.transform_keys { |k| k.to_s }
      new(
        api_key:        h['api_key'],
        token:          h['token'] || h['access_token'],
        account_id:     h['account_id'],
        base_url:       h['base_url'] || Configuration::DEFAULT_BASE_URL,
        webhook_secret: h['webhook_secret'],
        timeout:        h['timeout'] ? h['timeout'].to_i : Configuration::DEFAULT_TIMEOUT,
        logger:         h['logger']
      )
    end

    def upload_and_request_signatures(source:, signers:, message: nil,
                                       wait_for_ready: true, expires_at: nil,
                                       copy_receivers: nil, account_id: nil)
      if signers.nil? || signers.empty?
        raise ValidationError.new('At least one signer is required')
      end

      @logger.info("Starting upload and signature workflow for #{signers.length} signer(s)")

      upload_opts = {}
      upload_opts[:account_id] = account_id if account_id

      document = @documents.upload(source, upload_opts)
      @documents.wait_until_ready(document['id']) if wait_for_ready

      signer_ids = signers.map do |signer|
        s = signer.transform_keys { |k| k.to_s }
        payload = { full_name: s['full_name'] || s['name'], email: s['email'] }
        phone = s['whatsapp_phone_number'] || s['phone']
        payload[:whatsapp_phone_number] = phone if phone
        @signers.create(payload, account_id)['id']
      end

      assignment_payload = { method: 'virtual', signers: signer_ids }
      assignment_payload[:message]        = message        if message
      assignment_payload[:expires_at]     = expires_at     if expires_at
      assignment_payload[:copy_receivers] = copy_receivers if copy_receivers

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
