# frozen_string_literal: true

module Assinafy
  module Resources
    # Document upload, retrieval, download, lifecycle, and verification.
    #
    # See https://api.assinafy.com.br/v1/docs#document for the full
    # documentation of these endpoints.
    class DocumentResource < BaseResource
      MAX_UPLOAD_BYTES = 25 * 1024 * 1024
      READY_STATUSES   = %w[metadata_ready pending_signature certificated].freeze
      FAILED_STATUSES  = %w[failed rejected_by_signer rejected_by_user expired].freeze
      ARTIFACT_TYPES   = %w[original certificated certificate-page bundle pades].freeze

      # Upload a PDF and create a document.
      #
      # @param source [String, Hash] either a path to a PDF on disk, or a
      #   Hash with `:file_path` (path) **or** `:buffer` + `:file_name` (raw bytes).
      # @param options [Hash]
      # @option options [String] :name       optional display name for the document
      # @option options [String] :account_id override the client default
      # @return [Hash] document object
      # @raise [Assinafy::ValidationError] on invalid input or empty/non-PDF file
      # @raise [Assinafy::ApiError]        on a non-2xx response
      #
      # @see POST /accounts/{account_id}/documents
      # @example Upload a PDF from disk
      #   # Request: POST /accounts/{account_id}/documents (multipart/form-data)
      #   # Body: file=<binary application/pdf>, name="customer_agreement.pdf"
      #   client.documents.upload('/tmp/contract.pdf', name: 'customer_agreement.pdf')
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'resource' => 'document',
      #     'id' => '1032009d72b364f377ff270405cc',
      #     'account_id' => 'account-id',
      #     'template_id' => nil,
      #     'name' => 'customer_agreement.pdf',
      #     'status' => 'uploaded',
      #     'artifacts' => {
      #       'original' => 'https://sandbox.assinafy.com.br/v1/documents/<id>/download/original'
      #     },
      #     'is_closed' => false,
      #     'signing_url' => 'https://app-sandbox.assinafy.com.br/sign/1032009d72b364f377ff270405cc',
      #     'decline_reason' => nil,
      #     'declined_by' => nil,
      #     'tags' => [],
      #     'created_at' => '2026-06-05T21:21:12Z',
      #     'updated_at' => '2026-06-05T21:21:13Z',
      #     'pages' => []
      #   }
      # @example Upload raw bytes from memory
      #   client.documents.upload(buffer: pdf_bytes, file_name: 'in_memory.pdf')
      # @note The SDK enforces the `.pdf` extension and 25 MB limit; the API
      #   performs authoritative PDF-structure validation.
      def upload(source, options = {})
        options = require_payload(options, 'Upload options')
        buffer, file_name = read_source(source, max_bytes: MAX_UPLOAD_BYTES)
        validate_pdf_source!(buffer, file_name, max_bytes: MAX_UPLOAD_BYTES)

        acc_id = account_id(options[:account_id])

        @logger.info("Uploading document (#{buffer.bytesize} bytes)")

        payload = { file: file_part(buffer, file_name, 'application/pdf') }
        payload[:name] = options[:name] if options[:name]

        document = call('Document upload failed') do
          http_post("accounts/#{acc_id}/documents", payload)
        end

        document_id = uploaded_document_id(document)

        @logger.info("Document uploaded: #{document_id}")
        document
      end

      # List documents for an account.
      #
      # @param params [Hash] query parameters (`status`, `method`, `search`, `sort`, `tags`, `page`, `per_page`)
      # @param account_id_override [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [...], meta: { current_page:, per_page:, total:, last_page: } }`
      #
      # @see GET /accounts/{account_id}/documents
      # @example List the first page of documents
      #   # Request: GET /accounts/{account_id}/documents?per-page=3
      #   client.documents.list(per_page: 3)
      #
      #   # Response (unwrapped data payload):
      #   {
      #     data: [
      #       {
      #         'id' => '1031ff847e1aecdcf848f579cc77',
      #         'account_id' => 'account-id',
      #         'template_id' => nil,
      #         'name' => 'customer_agreement.pdf',
      #         'status' => 'metadata_ready',
      #         'artifacts' => {
      #           'original' => 'https://sandbox.assinafy.com.br/v1/documents/1031ff84.../download/original',
      #           'thumbnail' => 'https://sandbox.assinafy.com.br/v1/documents/1031ff84.../thumbnail'
      #         },
      #         'is_closed' => false,
      #         'signing_url' => 'https://app-sandbox.assinafy.com.br/sign/1031ff847e1aecdcf848f579cc77',
      #         'decline_reason' => nil,
      #         'declined_by' => nil,
      #         'tags' => [],
      #         'assignment' => nil,
      #         'pages' => [
      #           { 'id' => '1031ff84c23f85c38503ff0324d6', 'number' => 1, 'height' => 1651,
      #             'width' => 1275, 'download_url' => 'https://sandbox.assinafy.com.br/v1/documents/.../download' }
      #         ],
      #         'created_at' => '2026-06-05T20:50:31Z',
      #         'updated_at' => '2026-06-05T20:50:34Z'
      #       }
      #       # ... (one Hash per document)
      #     ],
      #     meta: { current_page: 1, per_page: 3, total: 14, last_page: 5 }
      #   }
      def list(params = {}, account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_list('Failed to list documents') do
          http_get("accounts/#{acc_id}/documents", params)
        end
      end

      # Lightweight search over an account's documents (id/name/status/artifacts),
      # without the heavier per-document detail returned by {#list}.
      #
      # @param query [String] free-text search term
      # @param params [Hash] extra query parameters (`status`, `page`, `per_page`, ...)
      # @param account_id_override [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [...], meta: {..} | nil }`
      # @see GET /accounts/{account_id}/documents/search
      # @example Search documents by name
      #   # Request: GET /accounts/{account_id}/documents/search?search=contract
      #   client.documents.search('contract')
      #
      #   # Response (unwrapped data payload):
      #   {
      #     data: [
      #       {
      #         'id' => '103b0253fdc3607d342c49f9b55d',
      #         'account_id' => 'account-id',
      #         'template_id' => nil,
      #         'name' => 'contract.pdf',
      #         'status' => 'metadata_ready',
      #         'artifacts' => { 'original' => 'https://...', 'thumbnail' => 'https://...' },
      #         'is_closed' => false,
      #         'signing_url' => 'https://app-sandbox.assinafy.com.br/sign/103b0253...',
      #         'tags' => [],
      #         'created_at' => '2026-07-20T15:53:37Z',
      #         'updated_at' => '2026-07-20T15:53:41Z'
      #       }
      #       # ... (one Hash per matching document)
      #     ],
      #     meta: nil
      #   }
      def search(query, params = {}, account_id_override = nil)
        acc_id = account_id(account_id_override)
        filters = require_payload(params, 'Document search parameters')

        call_list('Failed to search documents') do
          http_get("accounts/#{acc_id}/documents/search", filters.merge(search: query))
        end
      end

      # List the catalog of document status codes.
      #
      # @return [Array<Hash>] each entry has `code` and a `deletable` flag
      # @see GET /documents/statuses
      # @example List status codes
      #   # Request: GET /documents/statuses
      #   client.documents.statuses
      #
      #   # Response (unwrapped data payload):
      #   [
      #     { 'code' => 'uploading', 'deletable' => false },
      #     { 'code' => 'uploaded', 'deletable' => false },
      #     { 'code' => 'metadata_processing', 'deletable' => false },
      #     { 'code' => 'metadata_ready', 'deletable' => true },
      #     { 'code' => 'expired', 'deletable' => true },
      #     { 'code' => 'certificating', 'deletable' => false },
      #     { 'code' => 'certificated', 'deletable' => false },
      #     { 'code' => 'rejected_by_signer', 'deletable' => true },
      #     { 'code' => 'pending_signature', 'deletable' => true },
      #     { 'code' => 'rejected_by_user', 'deletable' => true },
      #     { 'code' => 'failed', 'deletable' => true }
      #   ]
      def statuses
        call_array('Failed to list document statuses') do
          http_get('documents/statuses')
        end
      end

      # Fetch a document by ID.
      #
      # @param document_id [String]
      # @return [Hash] document object (includes `assignment` once one exists, else nil)
      # @see GET /documents/{document_id}
      # @example Fetch a document
      #   # Request: GET /documents/{document_id}
      #   client.documents.details('1032009d72b364f377ff270405cc')
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'resource' => 'document',
      #     'id' => '1032009d72b364f377ff270405cc',
      #     'account_id' => 'account-id',
      #     'template_id' => nil,
      #     'name' => 'customer_agreement.pdf',
      #     'status' => 'metadata_ready',
      #     'artifacts' => {
      #       'original' => 'https://sandbox.assinafy.com.br/v1/documents/1032009d.../download/original',
      #       'thumbnail' => 'https://sandbox.assinafy.com.br/v1/documents/1032009d.../thumbnail'
      #     },
      #     'is_closed' => false,
      #     'signing_url' => 'https://app-sandbox.assinafy.com.br/sign/1032009d72b364f377ff270405cc',
      #     'decline_reason' => nil,
      #     'declined_by' => nil,
      #     'tags' => [],
      #     'assignment' => nil,
      #     'pages' => [
      #       { 'id' => '1032009db961c327b101a7fea34d', 'number' => 1, 'height' => 1651,
      #         'width' => 1275, 'download_url' => 'https://sandbox.assinafy.com.br/v1/documents/.../download' }
      #     ],
      #     'created_at' => '2026-06-05T21:21:12Z',
      #     'updated_at' => '2026-06-05T21:21:15Z'
      #   }
      def details(document_id)
        doc_id = require_id(document_id, 'Document ID')

        call('Failed to fetch document details') do
          http_get("documents/#{doc_id}")
        end
      end

      alias get details

      # Rename a document.
      #
      # @param document_id [String]
      # @param name        [String] the new display name
      # @return [Hash] the updated document object (envelope `data` unwrapped)
      # @see PATCH /documents/{document_id}
      # @example Rename a document
      #   # Request: PATCH /documents/{document_id}
      #   # Body: { "name": "renamed.pdf" }
      #   client.documents.rename('103b0253fdc3607d342c49f9b55d', 'renamed.pdf')
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'resource' => 'document',
      #     'id' => '103b0253fdc3607d342c49f9b55d',
      #     'account_id' => 'account-id',
      #     'name' => 'renamed.pdf',
      #     'status' => 'metadata_ready',
      #     'artifacts' => { 'original' => 'https://...', 'thumbnail' => 'https://...' },
      #     'is_closed' => false,
      #     'signing_url' => 'https://app-sandbox.assinafy.com.br/sign/103b0253...',
      #     'tags' => [],
      #     'created_at' => '2026-07-20T15:53:37Z',
      #     'updated_at' => '2026-07-20T15:53:41Z'
      #     # ... (see #details for the full document shape)
      #   }
      def rename(document_id, name)
        doc_id   = require_id(document_id, 'Document ID')
        new_name = require_present(name, 'Name')

        call('Failed to rename document') do
          http_patch("documents/#{doc_id}", body_params(name: new_name))
        end
      end

      # Poll {#details} until the document reaches a {READY_STATUSES ready} status,
      # raising if it reaches a {FAILED_STATUSES failed} status or the deadline elapses.
      #
      # @param document_id           [String]
      # @param max_wait_seconds      [Integer] total deadline (default: 30)
      # @param poll_interval_seconds [Integer] (default: 2)
      # @return [Hash] the document once it is ready
      # @raise [Assinafy::Error] on timeout or terminal failed status
      # @example Block until a freshly uploaded document is processed
      #   # Polls GET /documents/{document_id} every 2s until status is ready.
      #   client.documents.wait_until_ready('1032009d72b364f377ff270405cc', max_wait_seconds: 30)
      #
      #   # Response (unwrapped data payload): same shape as #details, with a ready status:
      #   {
      #     'resource' => 'document',
      #     'id' => '1032009d72b364f377ff270405cc',
      #     'status' => 'metadata_ready', # one of READY_STATUSES
      #     # ... (see #details for the full document shape)
      #   }
      def wait_until_ready(document_id, max_wait_seconds: 30, poll_interval_seconds: 2)
        doc_id = require_id(document_id, 'Document ID')
        unless max_wait_seconds.is_a?(Numeric) && max_wait_seconds > 0 &&
               poll_interval_seconds.is_a?(Numeric) && poll_interval_seconds > 0
          raise ValidationError.new('Wait and poll intervals must be positive numbers')
        end

        clock    = Process::CLOCK_MONOTONIC
        deadline = Process.clock_gettime(clock) + max_wait_seconds
        attempts = 0
        # @type var last_document: Assinafy::api_object?
        last_document = nil

        @logger.info("Waiting for document to be ready: #{doc_id}")

        while Process.clock_gettime(clock) < deadline
          attempts += 1
          begin
            doc = last_document = details(doc_id)
            status = doc['status'] || 'unknown'

            @logger.debug("Document status check #{attempts}: #{status}")

            return doc if READY_STATUSES.include?(status)

            raise_processing_error!(doc_id, doc, status) if FAILED_STATUSES.include?(status)
          rescue NetworkError => e
            @logger.warn("Error checking document status: #{e.message}")
          end

          remaining = deadline - Process.clock_gettime(clock)
          break unless remaining > 0

          sleep([poll_interval_seconds, remaining].min)
        end

        raise Assinafy::Error.new(
          'Timeout waiting for document to be ready',
          { document_id: doc_id, attempts: attempts, document: last_document }
        )
      end

      # Download a document artifact as raw bytes.
      #
      # @param document_id   [String]
      # @param artifact_name [String] `original`, `certificated`, `certificate-page`, `pades`, or
      #   `bundle` (default `certificated`)
      # @return [String] binary PDF body
      # @raise [Assinafy::ValidationError] on unknown artifact type
      # @see GET /documents/{document_id}/download/{artifact_name}
      # @example Download the original upload and save it to disk
      #   # Request: GET /documents/{document_id}/download/original
      #   bytes = client.documents.download('1032009d72b364f377ff270405cc', 'original')
      #
      #   # Response: raw bytes of the PDF (NOT a JSON envelope), e.g. a 607-byte String:
      #   bytes.class      # => String
      #   bytes.bytesize   # => 607
      #   File.binwrite('original.pdf', bytes)
      def download(document_id, artifact_name = 'certificated')
        doc_id = require_id(document_id, 'Document ID')
        art    = artifact_type(artifact_name)

        call_binary('Failed to download document') do
          http_get("documents/#{doc_id}/download/#{art}")
        end
      end

      # Download the document thumbnail (PNG/JPEG bytes).
      #
      # @param document_id [String]
      # @return [String] binary image body
      # @see GET /documents/{document_id}/thumbnail
      # @example Download the thumbnail and save it
      #   # Request: GET /documents/{document_id}/thumbnail
      #   bytes = client.documents.thumbnail('1032009d72b364f377ff270405cc')
      #
      #   # Response: raw image bytes (NOT a JSON envelope), e.g. a 4973-byte JPEG String:
      #   bytes.class               # => String
      #   bytes.byteslice(0, 4)     # => "\xFF\xD8\xFF\xE0" (JPEG magic bytes)
      #   File.binwrite('thumb.jpg', bytes)
      def thumbnail(document_id)
        doc_id = require_id(document_id, 'Document ID')

        call_binary('Failed to download document thumbnail') do
          http_get("documents/#{doc_id}/thumbnail")
        end
      end

      # Download a single page artifact.
      #
      # @param document_id [String]
      # @param page_id     [String]
      # @return [String] binary image body
      # @see GET /documents/{document_id}/pages/{page_id}/download
      # @example Download a single page image
      #   # Request: GET /documents/{document_id}/pages/{page_id}/download
      #   bytes = client.documents.download_page('1032009d72b364f377ff270405cc',
      #                                          '1032009db961c327b101a7fea34d')
      #
      #   # Response: raw image bytes (NOT a JSON envelope):
      #   bytes.class      # => String
      #   File.binwrite('page-1.png', bytes)
      def download_page(document_id, page_id)
        doc_id = require_id(document_id, 'Document ID')
        pid    = require_id(page_id, 'Page ID')

        call_binary('Failed to download page') do
          http_get("documents/#{doc_id}/pages/#{pid}/download")
        end
      end

      # List the activity log for a document.
      #
      # @param document_id [String]
      # @return [Array<Hash>] newest-first activity entries (empty Array when there are none)
      # @see GET /documents/{documentId}/activities
      # @example List a document's activity log
      #   # Request: GET /documents/{document_id}/activities
      #   client.documents.activities('1032009d72b364f377ff270405cc')
      #
      #   # Response (unwrapped data payload):
      #   [
      #     {
      #       'id' => 8304,
      #       'event' => 'document_metadata_ready',
      #       'message' => 'Documento processado.',
      #       'payload' => [],
      #       'origin' => nil,
      #       'created_at' => '2026-06-05T21:21:15Z'
      #     },
      #     {
      #       'id' => 8303,
      #       'event' => 'document_uploaded',
      #       'message' => 'Documento criado.',
      #       'payload' => [],
      #       'origin' => { 'ip' => '99.75.13.162', 'user-agent' => 'assinafy-ruby-sdk/1.3.1' },
      #       'created_at' => '2026-06-05T21:21:13Z'
      #     }
      #   ]
      def activities(document_id)
        doc_id = require_id(document_id, 'Document ID')

        call_array('Failed to fetch document activities') do
          http_get("documents/#{doc_id}/activities")
        end
      end

      # Permanently delete a document. Only allowed for "deletable" statuses.
      #
      # @param document_id [String]
      # @return [nil]
      # @see DELETE /documents/{documentId}
      # @example Delete a deletable document
      #   # Request: DELETE /documents/{document_id}
      #   client.documents.delete('1032009d72b364f377ff270405cc')
      #
      #   # Response: the API returns { "status": 200, "data": [] }; the SDK returns nil.
      #   # => nil
      def delete(document_id)
        doc_id = require_id(document_id, 'Document ID')

        call_void('Failed to delete document') do
          http_delete("documents/#{doc_id}")
        end
      end

      # Create a document from a template, optionally creating its virtual assignment.
      #
      # @param template_id          [String]
      # @param signers_or_payload   [Array<Hash>, Hash] signer references (`role_id` + `id`)
      #   or a full payload Hash. When a Hash is passed, `options` is merged into it.
      # @param options              [Hash] additional body fields (`name`, `message`,
      #   `editor_fields`, `expires_at`, ...)
      # @param account_id_override  [String, nil]
      # @return [Hash] document object with an embedded `assignment` (signers, items, signing_urls)
      #
      # @see POST /accounts/{account_id}/templates/{template_id}/documents
      # @example Create a document from a template with two signers
      #   # Request: POST /accounts/{account_id}/templates/{template_id}/documents
      #   # Body: {
      #   #   "name": "sample-contract.pdf",
      #   #   "message": "Message to the signers",
      #   #   "signers": [
      #   #     { "role_id": "fa8c14f3...", "id": "fa8c140c...", "verification_method": "Email",
      #   #       "notification_methods": ["Email"], "step": 1 }
      #   #   ],
      #   #   "expires_at": "2024-07-30T23:59:00Z"
      #   # }
      #   client.documents.create_from_template(
      #     '60f720572d7fecf7c16c8463',
      #     [{ role_id: 'fa8c14f3...', id: 'fa8c140c...' }],
      #     name: 'sample-contract.pdf', message: 'Message to the signers'
      #   )
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'resource' => 'document',
      #     'id' => 'fa8c140c614c928f7e7efa086b2',
      #     'account_id' => '1a',
      #     'template_id' => 'fa8c140b5ee344f8e48236ed284',
      #     'name' => 'sample-contract.pdf',
      #     'status' => 'uploaded',
      #     'assignment' => {
      #       'id' => 'fa8c140ccd5781b079738d19e95',
      #       'method' => 'virtual',
      #       'signers' => [{ 'id' => 'fa8c140c...', 'full_name' => 'Suzana Cordeiro',
      #                       'email' => 'signer@example.com', 'has_accepted_terms' => false }],
      #       'summary' => { 'signer_count' => 1, 'completed_count' => 0, 'signers' => [] },
      #       'signing_urls' => [{ 'signer_id' => 'customid1', 'url' => 'https://.../sign/...' }]
      #       # ... (also items, copy_receivers, expires_at, message)
      #     },
      #     'tags' => [{ 'id' => 'ab12cd34...', 'name' => 'Onboarding' }],
      #     'created_at' => '2024-07-23T15:05:17Z',
      #     'updated_at' => '2024-07-23T15:05:17Z'
      #     # ... (artifacts, pages, is_closed, decline_reason; see docs for full shape)
      #   }
      def create_from_template(template_id, signers_or_payload, options = {}, account_id_override = nil)
        tmpl_id = require_id(template_id, 'Template ID')
        acc_id  = account_id(account_id_override)
        body    = template_body(signers_or_payload, options)

        @logger.info("Creating document from template #{tmpl_id} for account #{acc_id}")

        call('Failed to create document from template') do
          http_post("accounts/#{acc_id}/templates/#{tmpl_id}/documents", body)
        end
      end

      # Estimate the cost of creating a document from a template without consuming credits.
      #
      # @param template_id          [String]
      # @param signers_or_payload   [Array<Hash>, Hash] signers with required +role_id+ and
      #   optional +verification_method+ / +notification_methods+; signer IDs are not required
      # @param account_id_override  [String, nil]
      # @return [Hash] cost breakdown with current account balances
      #
      # @see POST /accounts/{account_id}/templates/{template_id}/documents/estimate-cost
      # @example Estimate cost before creating from a template
      #   # Request: POST /accounts/{account_id}/templates/{template_id}/documents/estimate-cost
      #   # Body: { "signers": [{ "role_id": "fa8c14f3...", "notification_methods": ["Email"] }] }
      #   client.documents.estimate_cost_from_template(
      #     '60f720572d7fecf7c16c8463',
      #     [{ role_id: 'fa8c14f3...', notification_methods: ['Email'] }]
      #   )
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'documents' => 1,
      #     'credits' => 0,
      #     'needs_extra_document' => false,
      #     'extra_document_cost' => 0,
      #     'total_credits' => 0,
      #     'breakdown' => [], # [{ 'code'=>'NotificationWhatsapp', 'cost'=>0.45, 'quantity'=>1, ... }]
      #     'document_balance' => 62,
      #     'credit_balance' => 0,
      #     'has_sufficient_resources' => true,
      #     'blocking_reason' => nil, # e.g. 'PendingPayment' / 'InsufficientDocuments' when blocked
      #     'message' => nil
      #   }
      def estimate_cost_from_template(template_id, signers_or_payload, account_id_override = nil)
        tmpl_id = require_id(template_id, 'Template ID')
        acc_id  = account_id(account_id_override)
        body    = template_body(signers_or_payload)

        call('Failed to estimate cost from template') do
          http_post("accounts/#{acc_id}/templates/#{tmpl_id}/documents/estimate-cost", body)
        end
      end

      # Verify a certificated document by its signature hash.
      #
      # @param hash [String]
      # @return [Hash] verification result; `is_valid` is false when the hash is unknown
      # @see GET /documents/{signature_hash}/verify
      # @example Verify a certificated document
      #   # Request: GET /documents/{signature_hash}/verify
      #   client.documents.verify('FE32EDDADE7CBDDCBB934E7402047450B0E59C02')
      #
      #   # Response (unwrapped data payload) - verified:
      #   {
      #     'hash' => 'FE32EDDADE7CBDDCBB934E7402047450B0E59C02',
      #     'id' => '63ddb172402799bfc991d10d',
      #     'status' => 'certificated',
      #     'page_count' => '1',
      #     'signer_count' => '1',
      #     'completed_count' => 1,
      #     'completed_at' => '2023-01-27T19:27:44Z',
      #     'verified_at' => '2023-01-27T19:27:46Z',
      #     'is_valid' => true,
      #     'message' => ''
      #   }
      #   # Not verified: { 'hash' => 'INVALIDHASHEXAMPLE', 'id' => nil, 'status' => nil,
      #   #   'is_valid' => false, 'message' => 'Document not signed or not found.', ... }
      def verify(hash)
        h = require_id(hash, 'Signature hash')

        call('Failed to verify document') do
          http_get("documents/#{h}/verify", {}, workspace_auth: false)
        end
      end

      # Fetch the unauthenticated, public-facing metadata of a document. The
      # OpenAPI declares the full Document schema, while the current sandbox
      # returns the smaller payload shown below; the SDK passes either through.
      #
      # @param document_id [String]
      # @return [Hash] a Document Hash, or the current sandbox's minimal metadata Hash
      # @see GET /public/documents/{document_id}
      # @example Fetch public-facing document info (no auth required)
      #   # Request: GET /public/documents/{document_id}
      #   client.documents.public_info('39adfe3r5a3a')
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'resource' => 'document',
      #     'id' => 'doc1',
      #     'name' => '1.pdf',
      #     'page_count' => '1',
      #     'created_by' => 'John Smith'
      #   }
      def public_info(document_id)
        doc_id = require_id(document_id, 'Document ID')

        call('Failed to fetch public document info') do
          http_get("public/documents/#{doc_id}", {}, workspace_auth: false)
        end
      end

      # Send a 6-digit access token for the document to a signer (public endpoint).
      # The current OpenAPI permits no body or an `{ email: }` body, while the
      # deployed sandbox requires `{ recipient:, channel: }` when a recipient is supplied.
      #
      # @param document_id [String]
      # @param recipient   [String, nil] deployed-API email address or WhatsApp phone number
      # @param channel     [String, nil] deployed-API `email` or `whatsapp` channel
      # @param email       [String, nil] email address for the current OpenAPI request shape
      # @return [nil, Hash] `nil` for the OpenAPI's no-data envelope; the current
      #   sandbox returns `{ 'document' => {..}, 'channel' => String, 'recipient' => String }`
      # @see PUT /public/documents/{document_id}/send-token
      # @example Ask the API to use the document's signer contact (no auth required)
      #   client.documents.send_token('document-id')
      #
      # @example Email a signer using the current OpenAPI request (no auth required)
      #   # Request: PUT /public/documents/{document_id}/send-token
      #   # Body: { "email": "signer@example.com" }
      #   client.documents.send_token('document-id', email: 'signer@example.com')
      #
      # @example Use the current sandbox request shape
      #   # Body: { "recipient": "signer@example.com", "channel": "email" }
      #   client.documents.send_token('document-id', recipient: 'signer@example.com', channel: 'email')
      #
      #   # Current sandbox response (unwrapped data payload):
      #   {
      #     'document' => {
      #       'resource' => 'document',
      #       'id' => 'doc1',
      #       'name' => '1.pdf',
      #       'page_count' => '1',
      #       'created_by' => 'John Smith'
      #     },
      #     'channel' => 'email',
      #     'recipient' => 'signer@example.com'
      #   }
      #   # => nil when the API returns the documented no-data envelope
      def send_token(document_id, recipient: nil, channel: nil, email: nil)
        doc_id = require_id(document_id, 'Document ID')
        if email.nil? && recipient.nil? && channel.nil?
          payload = nil
        elsif !email.nil?
          if recipient || channel
            raise ValidationError.new('Use either email or recipient/channel, not both')
          end

          payload = { email: require_present(email, 'Email') }
        else
          require_present(recipient, 'Recipient')
          delivery_channel = require_present(channel, 'Channel').to_s
          unless %w[email whatsapp].include?(delivery_channel)
            raise ValidationError.new('Channel must be email or whatsapp')
          end

          payload = { recipient: recipient, channel: delivery_channel }
        end

        call('Failed to send signer token') do
          http_put("public/documents/#{doc_id}/send-token", payload && body_params(payload), workspace_auth: false)
        end
      end

      # List tags attached to a document.
      #
      # @param document_id [String]
      # @param account_id_override [String, nil]
      # @return [Array<Hash>] the document's tag objects
      # @see GET /accounts/{account_id}/documents/{document_id}/tags
      # @example List the tags attached to a document
      #   # Request: GET /accounts/{account_id}/documents/{document_id}/tags
      #   client.documents.list_tags('1032009d72b364f377ff270405cc')
      #
      #   # Response (unwrapped data payload):
      #   [
      #     {
      #       'id' => '1032009e69e366ca5adc879ef26c',
      #       'name' => 'customer-agreement',
      #       'color' => 'ff8800',
      #       'created_at' => '2026-06-05T21:21:19Z',
      #       'updated_at' => '2026-06-05T21:21:19Z'
      #     }
      #   ]
      def list_tags(document_id, account_id_override = nil)
        acc_id = account_id(account_id_override)
        doc_id = require_id(document_id, 'Document ID')

        call_array('Failed to list document tags') do
          http_get("accounts/#{acc_id}/documents/#{doc_id}/tags")
        end
      end

      # Replace the document's full tag set. Passing an empty array detaches
      # all tags from the document.
      #
      # @param document_id [String]
      # @param tags [Array<String>] tag IDs per OpenAPI; the deployed sandbox also accepts existing names
      # @param account_id_override [String, nil]
      # @return [Array<Hash>] the document's full tag set after replacement (empty Array when detaching all)
      # @see PUT /accounts/{account_id}/documents/{document_id}/tags
      # @example Replace the tag set with a single tag
      #   # Request: PUT /accounts/{account_id}/documents/{document_id}/tags
      #   # Body: { "tags": ["ab12c09f3e709a8a1c82d69b145"] }
      #   client.documents.replace_tags('1032009d72b364f377ff270405cc', ['ab12c09f3e709a8a1c82d69b145'])
      #
      #   # Response (unwrapped data payload):
      #   [
      #     {
      #       'id' => 'ab12c09f3e709a8a1c82d69b145',
      #       'name' => 'Contracts',
      #       'color' => nil,
      #       'created_at' => '2026-05-14T12:00:00Z',
      #       'updated_at' => '2026-05-14T12:00:00Z'
      #     }
      #   ]
      #   # Passing [] detaches all tags and returns [].
      def replace_tags(document_id, tags, account_id_override = nil)
        acc_id = account_id(account_id_override)
        doc_id = require_id(document_id, 'Document ID')

        call_array('Failed to replace document tags') do
          http_put("accounts/#{acc_id}/documents/#{doc_id}/tags",
                   body_params(tags: tag_names(tags, allow_empty: true)))
        end
      end

      # Attach additional tags to a document without removing existing tags.
      #
      # @param document_id [String]
      # @param tags [Array<String>] tag IDs per OpenAPI; the deployed sandbox also accepts existing names
      # @param account_id_override [String, nil]
      # @return [Array<Hash>] the document's full tag set after the append
      # @see POST /accounts/{account_id}/documents/{document_id}/tags
      # @example Attach a tag without removing existing ones
      #   # Request: POST /accounts/{account_id}/documents/{document_id}/tags
      #   # Body: { "tags": ["1032009e69e366ca5adc879ef26c"] }
      #   client.documents.append_tags('1032009d72b364f377ff270405cc', ['1032009e69e366ca5adc879ef26c'])
      #
      #   # Response (unwrapped data payload):
      #   [
      #     {
      #       'id' => '1032009e69e366ca5adc879ef26c',
      #       'name' => 'customer-agreement',
      #       'color' => 'ff8800',
      #       'created_at' => '2026-06-05T21:21:19Z',
      #       'updated_at' => '2026-06-05T21:21:19Z'
      #     }
      #   ]
      def append_tags(document_id, tags, account_id_override = nil)
        acc_id = account_id(account_id_override)
        doc_id = require_id(document_id, 'Document ID')

        call_array('Failed to append document tags') do
          http_post("accounts/#{acc_id}/documents/#{doc_id}/tags",
                    body_params(tags: tag_names(tags)))
        end
      end

      # Detach a single tag from a document. The tag itself is not deleted.
      #
      # @param document_id [String]
      # @param tag_id [String]
      # @param account_id_override [String, nil]
      # @return [Hash] `{ 'detached' => true }`
      # @see DELETE /accounts/{account_id}/documents/{document_id}/tags/{tag_id}
      # @example Detach a single tag from a document
      #   # Request: DELETE /accounts/{account_id}/documents/{document_id}/tags/{tag_id}
      #   client.documents.detach_tag('1032009d72b364f377ff270405cc', 'fa8c09f3e709a8a1c82d69b1454')
      #
      #   # Response (unwrapped data payload):
      #   { 'detached' => true }
      #   # Detaching a tag that was not attached is a no-op (still returns { 'detached' => true }).
      def detach_tag(document_id, tag_id, account_id_override = nil)
        acc_id = account_id(account_id_override)
        doc_id = require_id(document_id, 'Document ID')
        tid    = require_id(tag_id, 'Tag ID')

        call('Failed to detach document tag') do
          http_delete("accounts/#{acc_id}/documents/#{doc_id}/tags/#{tid}")
        end
      end

      # Convenience: true when the document is `certificated`, or when the
      # embedded assignment summary reports all signers complete.
      #
      # @param document_id [String]
      # @return [Boolean]
      # @example Check whether every signer has completed
      #   # Fetches GET /documents/{document_id} and inspects status + assignment.summary.
      #   client.documents.fully_signed?('1032009d72b364f377ff270405cc')
      #
      #   # Return value (computed locally from the document, not a server payload):
      #   # => false  (true when status == 'certificated', or every signer in
      #   #            assignment.summary is completed)
      def fully_signed?(document_id)
        doc = details(document_id)
        return true if doc['status'] == 'certificated'

        summary = doc.dig('assignment', 'summary')
        if summary && summary['signer_count'].is_a?(Integer)
          summary['signer_count'] > 0 && summary['signer_count'] == summary['completed_count']
        else
          false
        end
      end

      # Convenience: derive a {signed, total, pending, percentage} progress
      # Hash from the document's assignment summary.
      #
      # @param document_id [String]
      # @return [Hash{Symbol=>Integer,Float}]
      # @example Derive signing progress from the document's assignment summary
      #   # Fetches GET /documents/{document_id} and reduces assignment.summary locally.
      #   client.documents.signing_progress('1032009d72b364f377ff270405cc')
      #
      #   # Return value (computed locally; percentage is signed/total rounded to 2 decimals):
      #   { signed: 0, total: 0, pending: 0, percentage: 0.0 }
      def signing_progress(document_id)
        doc     = details(document_id)
        summary = doc.dig('assignment', 'summary')
        signers = doc.dig('assignment', 'signers') || []

        total      = (summary && summary['signer_count']) || signers.length
        signed     = (summary && summary['completed_count']) || 0
        pending    = [total - signed, 0].max
        percentage = total > 0 ? (signed.to_f / total * 10_000).round / 100.0 : 0.0

        { signed: signed, total: total, pending: pending, percentage: percentage }
      end

      private

      def uploaded_document_id(document)
        id = document['id'] if document.is_a?(Hash)
        require_id(id, 'Uploaded document ID')
      rescue ValidationError
        raise Assinafy::Error.new(
          'Upload succeeded but no usable document ID was returned',
          { document: document }
        )
      end

      def raise_processing_error!(document_id, document, status)
        raise Assinafy::Error.new(
          "Document processing failed with status: #{status}",
          { document_id: document_id, document: document }
        )
      end

      def template_body(signers_or_payload, options = {})
        body =
          if signers_or_payload.is_a?(Hash)
            signers_or_payload.merge(options)
          else
            options.merge(signers: signers_or_payload)
          end

        unless body[:signers] || body['signers']
          raise ValidationError.new('signers are required')
        end

        require_array(body[:signers] || body['signers'], 'Signers').each do |signer|
          require_payload(signer, 'Signer')
        end

        body_params(body)
      end

      def tag_names(tags, allow_empty: false)
        unless tags.is_a?(Array)
          raise ValidationError.new('Tags must be an Array')
        end

        if tags.empty? && !allow_empty
          raise ValidationError.new('Tags must be a non-empty Array')
        end

        tags.each do |tag|
          raise ValidationError.new('Tags must contain only Strings') unless tag.is_a?(String)

          require_present(tag, 'Tag name')
        end

        tags
      end

      def artifact_type(artifact_name)
        value = require_id(artifact_name, 'Artifact name').to_s
        return value if ARTIFACT_TYPES.include?(value)

        raise ValidationError.new('Invalid artifact type', { artifact_name: artifact_name })
      end
    end
  end
end
