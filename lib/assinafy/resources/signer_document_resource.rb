# frozen_string_literal: true

module Assinafy
  module Resources
    # Signer-authenticated views over their assigned documents. All endpoints
    # accept either the workspace `Authorization` header or the
    # `signer-access-code` URL parameter for authentication.
    #
    # See https://api.assinafy.com.br/v1/docs#signer for the full
    # documentation of these endpoints.
    class SignerDocumentResource < BaseResource
      # Fetch the signer's "current" document (the one referenced by the access code).
      #
      # @param signer_id          [String]
      # @param signer_access_code [String]
      # @return [Hash]
      # @see GET /signers/{signer_id}/document
      def current(signer_id, signer_access_code:)
        sid = require_id(signer_id, 'Signer ID')

        call('Failed to fetch signer document') do
          http_get("signers/#{sid}/document", signer_access_code: signer_access_code)
        end
      end

      alias document current

      # List all documents the signer has access to, with pagination metadata.
      #
      # @param signer_id          [String]
      # @param params             [Hash] `status`, `method`, `search`, `sort`, `page`, `per_page`
      # @param signer_access_code [String]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [...], meta: { ... } }`
      # @see GET /signers/{signer_id}/documents
      def list(signer_id, params = {}, signer_access_code:)
        sid = require_id(signer_id, 'Signer ID')

        call_list('Failed to list signer documents') do
          http_get("signers/#{sid}/documents", params.merge(signer_access_code: signer_access_code))
        end
      end

      # Sign multiple virtual-method documents in a single call.
      #
      # @param document_ids       [Array<String>]
      # @param signer_access_code [String]
      # @return [Hash]
      # @see PUT /signers/documents/sign-multiple
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
      # @return [Hash]
      # @see PUT /signers/documents/decline-multiple
      def decline_multiple(document_ids, decline_reason:, signer_access_code:)
        ids    = require_array(document_ids, 'Document IDs')
        reason = require_id(decline_reason, 'Decline reason')

        call('Failed to decline documents') do
          http_put('signers/documents/decline-multiple',
                   body_params(document_ids: ids, decline_reason: reason),
                   signer_access_code: signer_access_code)
        end
      end

      # Download an artifact for one of the signer's documents.
      #
      # @param signer_id          [String]
      # @param document_id        [String]
      # @param artifact_name      [String] one of `original`, `certificated`, `certificate-page`, `bundle`
      # @param signer_access_code [String]
      # @return [String] binary file body
      # @see GET /signers/{signer_id}/documents/{document_id}/download/{artifact_name}
      def download(signer_id, document_id, artifact_name = 'certificated', signer_access_code:)
        sid = require_id(signer_id, 'Signer ID')
        did = require_id(document_id, 'Document ID')
        art = require_id(artifact_name, 'Artifact name')

        call_binary('Failed to download signer document') do
          http_get("signers/#{sid}/documents/#{did}/download/#{art}",
                   signer_access_code: signer_access_code)
        end
      end
    end
  end
end
