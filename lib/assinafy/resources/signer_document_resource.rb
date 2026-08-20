# frozen_string_literal: true

module Assinafy
  module Resources
    # Signer-authenticated views over a signer's assigned documents.
    #
    # Authentication varies by endpoint (verified against the live API):
    #
    # - {#current}/{#document}, {#sign_multiple}, {#decline_multiple} require the
    #   `signer-access-code` URL parameter.
    # - {#list} accepts EITHER the workspace `X-Api-Key` header OR the access
    #   code; pass `signer_access_code:` only when authenticating as the signer.
    # - {#download} only needs the document/artifact IDs.
    #
    # See https://api.assinafy.com.br/v1/docs#signer for the full
    # documentation of these endpoints.
    class SignerDocumentResource < BaseResource
      # Fetch the signer's "current" document (the one referenced by the access code).
      #
      # Resolves the document, assignment, and current signer directly from the
      # access code; it does not require code verification or data confirmation.
      # The shape mirrors the signing endpoints, and `assignment.items` is
      # filtered to only the current signer's items.
      #
      # @param signer_id          [String]
      # @param signer_access_code [String]
      # @return [Hash] the document (envelope `data` unwrapped)
      # @see GET /signers/{signer_id}/document
      # @example Fetch the document tied to an access code
      #   doc = client.signer_documents.current('signer-id', signer_access_code: 'signer-access-code')
      #
      #   # => {
      #   #   "id"             => "document-id",
      #   #   "account_id"     => "account-id",
      #   #   "name"           => "my_document.pdf",
      #   #   "status"         => "metadata_ready",
      #   #   "artifacts"      => { "original" => "https://...", "thumbnail" => "https://..." },
      #   #   "is_closed"      => false,
      #   #   "signing_url"    => "https://app.assinafy.com.br/sign/doc1",
      #   #   "decline_reason" => nil,
      #   #   "declined_by"    => nil,
      #   #   "created_at"     => "2023-07-21T13:43:17Z",
      #   #   "updated_at"     => "2023-07-21T13:43:17Z",
      #   #   "current_signer" => { "id" => "signer-id", "full_name" => "Signer Name",
      #   #                         "email" => "signer@example.com",
      #   #                         "verification_method" => "Email", "notification_methods" => ["Email"] },
      #   #   "assignment"     => { "id" => "1", "method" => "virtual", "items" => [{ ... }] }
      #   #   # ... (see docs for full shape)
      #   # }
      def current(signer_id, signer_access_code:)
        sid = require_id(signer_id, 'Signer ID')

        call('Failed to fetch signer document') do
          http_get("signers/#{sid}/document", signer_access_code: signer_access_code)
        end
      end

      alias document current

      # List all documents the signer has access to, with pagination metadata.
      # This endpoint accepts either the workspace `X-Api-Key` header or the
      # signer access code, so `signer_access_code:` is optional here; when nil
      # it is omitted from the query and the header auth is used.
      #
      # @param signer_id          [String]
      # @param params             [Hash] documented `page` and `per_page` query parameters
      # @param signer_access_code [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [...], meta: { current_page:, per_page:, total:, last_page: } }`
      # @see GET /signers/{signer_id}/documents
      # @example List the signer's documents with pagination
      #   page = client.signer_documents.list('signer-id',
      #                                       { page: 1, per_page: 15 },
      #                                       signer_access_code: 'signer-access-code')
      #
      #   # => {
      #   #   data: [
      #   #     {
      #   #       "id"         => "document-id",
      #   #       "account_id" => "account-id",
      #   #       "name"       => "my_document.pdf",
      #   #       "status"     => "metadata_ready",
      #   #       "assignment" => { "id" => "1", "method" => "virtual", "signers" => [{ ... }],
      #   #                         "items" => [{ ... }], "summary" => { "signer_count" => 2, ... } },
      #   #       "artifacts"  => { "original" => "https://...", "thumbnail" => "https://..." },
      #   #       "pages"      => [{ "id" => "...", "number" => 1, "height" => 1, "width" => 1,
      #   #                          "download_url" => "https://..." }],
      #   #       "is_closed"  => false
      #   #       # ... (see docs for full shape)
      #   #     }
      #   #   ],
      #   #   meta: { current_page: 1, per_page: 15, total: 1, last_page: 1 }
      #   # }
      def list(signer_id, params = {}, signer_access_code: nil)
        sid = require_id(signer_id, 'Signer ID')

        call_list('Failed to list signer documents') do
          http_get("signers/#{sid}/documents", params.merge(signer_access_code: signer_access_code))
        end
      end

      # Lightweight search over the signer's documents. Like {#list}, this
      # accepts either the workspace `X-Api-Key` header or the signer access
      # code, so `signer_access_code:` is optional.
      #
      # @param signer_id          [String]
      # @param query              [String] free-text search term
      # @param params             [Hash] optional deployment-specific query parameters
      # @param signer_access_code [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [...], meta: {..} | nil }`
      # @see GET /signers/{signer_id}/documents/search
      # @example Search the signer's documents
      #   page = client.signer_documents.search('signer-id', 'contract')
      #
      #   # Request: GET /signers/{signer_id}/documents/search?search=contract
      #   # => {
      #   #   data: [
      #   #     { "id" => "document-id", "account_id" => "account-id", "name" => "contract.pdf",
      #   #       "status" => "pending_signature", "template_id" => nil,
      #   #       "artifacts" => { "original" => "https://...", "thumbnail" => "https://..." },
      #   #       "is_closed" => false, "signing_url" => "https://...", "tags" => []
      #   #       # ... search returns the lightweight document shape (no embedded assignment)
      #   #     }
      #   #   ],
      #   #   meta: nil
      #   # }
      def search(signer_id, query, params = {}, signer_access_code: nil)
        sid = require_id(signer_id, 'Signer ID')

        call_list('Failed to search signer documents') do
          http_get("signers/#{sid}/documents/search",
                   params.merge(search: query, signer_access_code: signer_access_code))
        end
      end

      # Sign multiple virtual-method documents in a single call.
      #
      # Each document must be prepared for the "virtual" signature method.
      #
      # @param document_ids       [Array<String>]
      # @param signer_access_code [String]
      # @return [Array] empty array on success (envelope `data` unwrapped)
      # @see PUT /signers/documents/sign-multiple
      # @example Sign two documents at once
      #   client.signer_documents.sign_multiple(%w[document-1 document-2],
      #                                             signer_access_code: 'signer-access-code')
      #
      #   # Request body the SDK sends:
      #   #   { "document_ids": ["document-1", "document-2"] }
      #
      #   # => []
      def sign_multiple(document_ids, signer_access_code:)
        ids = require_array(document_ids, 'Document IDs')

        call('Failed to sign documents') do
          http_put('signers/documents/sign-multiple',
                   body_params(document_ids: ids),
                   signer_access_code: signer_access_code)
        end
      end

      # Decline multiple documents in a single call.
      #
      # @param document_ids       [Array<String>]
      # @param decline_reason     [String]
      # @param signer_access_code [String]
      # @return [Array] empty array on success (envelope `data` unwrapped)
      # @see PUT /signers/documents/decline-multiple
      # @example Decline two documents with a reason
      #   client.signer_documents.decline_multiple(%w[document-1 document-2],
      #                                            decline_reason: 'Unfavorable terms.',
      #                                            signer_access_code: 'signer-access-code')
      #
      #   # Request body the SDK sends:
      #   #   { "document_ids": ["document-1", "document-2"], "decline_reason": "Unfavorable terms." }
      #
      #   # => []
      def decline_multiple(document_ids, decline_reason:, signer_access_code:)
        ids    = require_array(document_ids, 'Document IDs')
        reason = require_present(decline_reason, 'Decline reason')

        call('Failed to decline documents') do
          http_put('signers/documents/decline-multiple',
                   body_params(document_ids: ids, decline_reason: reason),
                   signer_access_code: signer_access_code)
        end
      end

      # Download an artifact for one of the signer's documents.
      #
      # This endpoint is public (no auth required) — only the document and
      # artifact IDs are needed — so `signer_access_code:` is optional and
      # omitted from the query when nil.
      #
      # @param signer_id          [String]
      # @param document_id        [String]
      # @param artifact_name      [String] `original`, `certificated`, `certificate-page`, `pades`, or
      #   `bundle`
      # @param signer_access_code [String, nil] optional
      # @return [String] binary file body (ASCII-8BIT), e.g. the raw PDF bytes
      # @see GET /signers/{signer_id}/documents/{document_id}/download/{artifact_name}
      # @example Download the original PDF and write it to disk (no access code needed)
      #   pdf = client.signer_documents.download('signer-id', 'document-id', 'original')
      #
      #   # Response is the raw artifact body (Content-Type: application/pdf):
      #   #   => "%PDF-1.7\n..." (binary string)
      #   File.binwrite('document.pdf', pdf)
      def download(signer_id, document_id, artifact_name = 'certificated', signer_access_code: nil)
        sid = require_id(signer_id, 'Signer ID')
        did = require_id(document_id, 'Document ID')
        art = require_id(artifact_name, 'Artifact name')
        unless DocumentResource::ARTIFACT_TYPES.include?(art)
          raise ValidationError.new('Invalid artifact type', { artifact_name: artifact_name })
        end

        call_binary('Failed to download signer document') do
          http_get("signers/#{sid}/documents/#{did}/download/#{art}",
                   signer_access_code: signer_access_code)
        end
      end
    end
  end
end
