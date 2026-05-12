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
      ARTIFACT_TYPES   = %w[original certificated certificate-page bundle].freeze

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
      def upload(source, options = {})
        buffer, file_name = load_source(source)
        validate_upload!(buffer, file_name)

        acc_id = account_id(options[:account_id])

        @logger.info("Uploading document #{file_name} (#{buffer.bytesize} bytes)")

        io      = StringIO.new(buffer)
        payload = { file: Faraday::FilePart.new(io, 'application/pdf', file_name) }
        payload[:name] = options[:name] if options[:name]

        document = call('Document upload failed') do
          http_post("accounts/#{acc_id}/documents", payload)
        end

        unless document.is_a?(Hash) && document['id']
          raise ValidationError.new('Upload succeeded but no document ID was returned')
        end

        @logger.info("Document uploaded: #{document['id']}")
        document
      end

      # List documents for an account.
      #
      # @param params [Hash] query parameters (`status`, `method`, `search`, `sort`, `page`, `per_page`)
      # @param account_id_override [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [...], meta: { current_page:, per_page:, total:, last_page: } }`
      #
      # @see GET /accounts/{account_id}/documents
      def list(params = {}, account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_list('Failed to list documents') do
          http_get("accounts/#{acc_id}/documents", params)
        end
      end

      # List the catalog of document status codes.
      #
      # @return [Array<Hash>]
      # @see GET /documents/statuses
      def statuses
        call('Failed to list document statuses') do
          http_get('documents/statuses')
        end
      end

      # Fetch a document by ID.
      #
      # @param document_id [String]
      # @return [Hash]
      # @see GET /documents/{document_id}
      def details(document_id)
        doc_id = require_id(document_id, 'Document ID')

        call('Failed to fetch document details') do
          http_get("documents/#{doc_id}")
        end
      end

      alias get details

      # Poll {#details} until the document reaches a {READY_STATUSES ready} status,
      # raising if it reaches a {FAILED_STATUSES failed} status or the deadline elapses.
      #
      # @param document_id           [String]
      # @param max_wait_seconds      [Integer] total deadline (default: 30)
      # @param poll_interval_seconds [Integer] (default: 2)
      # @return [Hash] the document once it is ready
      # @raise [Assinafy::ValidationError] on timeout or terminal failed status
      def wait_until_ready(document_id, max_wait_seconds: 30, poll_interval_seconds: 2)
        doc_id   = require_id(document_id, 'Document ID')
        deadline = Time.now + max_wait_seconds
        attempts = 0

        @logger.info("Waiting for document to be ready: #{doc_id}")

        while Time.now < deadline
          attempts += 1
          begin
            doc    = details(doc_id)
            status = doc['status'] || 'unknown'

            @logger.debug("Document status check #{attempts}: #{status}")

            return doc if READY_STATUSES.include?(status)

            if FAILED_STATUSES.include?(status)
              raise ValidationError.new("Document processing failed with status: #{status}")
            end
          rescue ValidationError
            raise
          rescue StandardError => e
            @logger.warn("Error checking document status: #{e.message}")
          end

          sleep(poll_interval_seconds)
        end

        raise ValidationError.new(
          'Timeout waiting for document to be ready',
          { document_id: doc_id, attempts: attempts }
        )
      end

      # Download a document artifact as raw bytes.
      #
      # @param document_id   [String]
      # @param artifact_name [String] one of {ARTIFACT_TYPES} (default `certificated`)
      # @return [String] binary PDF body
      # @raise [Assinafy::ValidationError] on unknown artifact type
      # @see GET /documents/{document_id}/download/{artifact_name}
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
      # @return [Array<Hash>]
      # @see GET /documents/{documentId}/activities
      def activities(document_id)
        doc_id = require_id(document_id, 'Document ID')

        result = call('Failed to fetch document activities') do
          http_get("documents/#{doc_id}/activities")
        end

        result || []
      end

      # Permanently delete a document. Only allowed for "deletable" statuses.
      #
      # @param document_id [String]
      # @return [nil]
      # @see DELETE /documents/{documentId}
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
      # @return [Hash] document object
      #
      # @see POST /accounts/{account_id}/templates/{template_id}/documents
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
      # @param signers_or_payload   [Array<Hash>, Hash] same shape as #create_from_template
      # @param account_id_override  [String, nil]
      # @return [Hash] cost breakdown
      #
      # @see POST /accounts/{account_id}/templates/{template_id}/documents/estimate-cost
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
      # @return [Hash]
      # @see GET /documents/{signature_hash}/verify
      def verify(hash)
        h = require_id(hash, 'Signature hash')

        call('Failed to verify document') do
          http_get("documents/#{h}/verify")
        end
      end

      # Fetch the unauthenticated, public-facing metadata of a document.
      #
      # @param document_id [String]
      # @return [Hash]
      # @see GET /public/documents/{document_id}
      def public_info(document_id)
        doc_id = require_id(document_id, 'Document ID')

        call('Failed to fetch public document info') do
          http_get("public/documents/#{doc_id}")
        end
      end

      # Send a 6-digit access token for the document to a signer (public endpoint).
      #
      # @param document_id [String]
      # @param recipient   [String] email address or WhatsApp phone number
      # @param channel     [String] `email` or `whatsapp`
      # @return [Hash]
      # @see PUT /public/documents/{document_id}/send-token
      def send_token(document_id, recipient:, channel:)
        doc_id = require_id(document_id, 'Document ID')

        call('Failed to send signer token') do
          http_put("public/documents/#{doc_id}/send-token",
                   body_params(recipient: recipient, channel: channel))
        end
      end

      # Convenience: true when the document is `certificated`, or when the
      # embedded assignment summary reports all signers complete.
      #
      # @param document_id [String]
      # @return [Boolean]
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

      def load_source(source)
        if source.is_a?(Hash) && source[:buffer]
          raise ValidationError.new('file_name is required when uploading a buffer') unless source[:file_name]

          [source[:buffer], source[:file_name]]
        elsif source.is_a?(Hash) && source[:file_path]
          file_path = source[:file_path]
          raise ValidationError.new('file_path is required') unless file_path

          [File.binread(file_path), source[:file_name] || File.basename(file_path)]
        elsif source.is_a?(String)
          [File.binread(source), File.basename(source)]
        else
          raise ValidationError.new('Invalid upload source: provide :file_path or :buffer')
        end
      end

      def validate_upload!(buffer, file_name)
        if buffer.nil? || buffer.bytesize == 0
          raise ValidationError.new('File buffer is empty', { file_name: file_name })
        end

        unless file_name.to_s.downcase.end_with?('.pdf')
          raise ValidationError.new('Only PDF files are supported', { file_name: file_name })
        end

        if buffer.bytesize > MAX_UPLOAD_BYTES
          raise ValidationError.new(
            'File size exceeds maximum allowed (25MB)',
            { file_size: buffer.bytesize, max_size: MAX_UPLOAD_BYTES }
          )
        end
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

        body_params(body)
      end

      def artifact_type(artifact_name)
        value = require_id(artifact_name, 'Artifact name').to_s
        return value if ARTIFACT_TYPES.include?(value)

        raise ValidationError.new('Invalid artifact type', { artifact_name: artifact_name })
      end
    end
  end
end
