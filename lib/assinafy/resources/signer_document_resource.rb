# frozen_string_literal: true

module Assinafy
  module Resources
    class SignerDocumentResource < BaseResource
      def current(signer_id, signer_access_code:)
        sid = require_id(signer_id, 'Signer ID')

        call('Failed to fetch signer document') do
          http_get("signers/#{sid}/document", signer_access_code: signer_access_code)
        end
      end

      alias document current

      def list(signer_id, params = {}, signer_access_code:)
        sid = require_id(signer_id, 'Signer ID')

        call_list('Failed to list signer documents') do
          http_get("signers/#{sid}/documents", params.merge(signer_access_code: signer_access_code))
        end
      end

      def sign_multiple(document_ids, signer_access_code:)
        ids = require_array(document_ids, 'Document IDs')

        call('Failed to sign documents') do
          http_put('signers/documents/sign-multiple',
                   body_params(document_ids: ids),
                   signer_access_code: signer_access_code)
        end
      end

      def decline_multiple(document_ids, decline_reason:, signer_access_code:)
        ids    = require_array(document_ids, 'Document IDs')
        reason = require_id(decline_reason, 'Decline reason')

        call('Failed to decline documents') do
          http_put('signers/documents/decline-multiple',
                   body_params(document_ids: ids, decline_reason: reason),
                   signer_access_code: signer_access_code)
        end
      end

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
