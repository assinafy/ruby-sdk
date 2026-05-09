# frozen_string_literal: true

module Assinafy
  module Resources
    class AssignmentResource < BaseResource
      OPTIONAL_FIELDS = %i[message expires_at copy_receivers].freeze

      class << self
        def build_payload(payload, options = {})
          p       = payload.transform_keys(&:to_sym)
          signers = extract_signer_refs(p)
          entries = p[:entries]
          method  = (p[:method] || 'virtual').to_s

          validate_method!(method, signers, entries, p)

          result = { method: method, signers: signers.map { |ref| normalise_signer_ref(ref, options) } }
          OPTIONAL_FIELDS.each { |key| result[key] = p[key] if p[key] }
          result[:entries] = entries if entries
          Utils.body_params(result)
        end

        private

        def validate_method!(method, signers, entries, payload)
          if method == 'virtual' && signers.empty?
            raise ValidationError.new(
              'At least one signer is required',
              { signers: payload[:signers] || payload[:signer_ids] || payload[:signerIds] }
            )
          end

          return unless method == 'collect' && (!entries.is_a?(Array) || entries.empty?)

          raise ValidationError.new('entries are required for collect assignments')
        end

        def extract_signer_refs(payload)
          return payload[:signers] if payload[:signers].is_a?(Array) && !payload[:signers].empty?

          legacy = payload[:signer_ids] || payload[:signerIds]
          legacy.is_a?(Array) ? legacy : []
        end

        def normalise_signer_ref(ref, options)
          return string_signer_ref(ref) if ref.is_a?(String)
          return hash_signer_ref(ref, options) if ref.is_a?(Hash)

          raise ValidationError.new('Invalid signer reference', { ref: ref })
        end

        def string_signer_ref(ref)
          raise ValidationError.new('Signer ID cannot be empty') if ref.empty?

          { id: ref }
        end

        def hash_signer_ref(ref, options)
          r  = ref.transform_keys(&:to_sym)
          id = r[:id] || r[:signer_id]

          normalised = {}
          normalised[:id]                   = id                        if id
          normalised[:verification_method]  = r[:verification_method]   if r[:verification_method]
          normalised[:notification_methods] = r[:notification_methods]  if r[:notification_methods]

          return normalised if id.is_a?(String) && !id.empty?
          return normalised.tap { |h| h.delete(:id) } if options[:allow_signers_without_id]

          raise ValidationError.new('Invalid signer reference', { ref: ref })
        end
      end

      def create(document_id, payload)
        doc_id = require_id(document_id, 'Document ID')
        body   = self.class.build_payload(payload)

        @logger.info("Creating assignment for document #{doc_id}")

        call('Failed to create assignment') do
          http_post("documents/#{doc_id}/assignments", body)
        end
      end

      def estimate_cost(document_id, payload)
        doc_id = require_id(document_id, 'Document ID')
        body   = self.class.build_payload(payload, allow_signers_without_id: true)

        call('Failed to estimate assignment cost') do
          http_post("documents/#{doc_id}/assignments/estimate-cost", body)
        end
      end

      def reset_expiration(document_id, assignment_id, expires_at)
        doc_id = require_id(document_id, 'Document ID')
        asg_id = require_id(assignment_id, 'Assignment ID')

        call('Failed to update assignment expiration') do
          http_put("documents/#{doc_id}/assignments/#{asg_id}/reset-expiration",
                   body_params(expires_at: expires_at))
        end
      end

      def resend_notification(document_id, assignment_id, signer_id)
        doc_id = require_id(document_id, 'Document ID')
        asg_id = require_id(assignment_id, 'Assignment ID')
        sid    = require_id(signer_id, 'Signer ID')

        call('Failed to resend signer notification') do
          http_put("documents/#{doc_id}/assignments/#{asg_id}/signers/#{sid}/resend")
        end
      end

      def estimate_resend_cost(document_id, assignment_id, signer_id)
        doc_id = require_id(document_id, 'Document ID')
        asg_id = require_id(assignment_id, 'Assignment ID')
        sid    = require_id(signer_id, 'Signer ID')

        call('Failed to estimate resend cost') do
          http_post("documents/#{doc_id}/assignments/#{asg_id}/signers/#{sid}/estimate-resend-cost")
        end
      end

      def signer_document(signer_access_code:, has_accepted_terms: nil)
        call('Failed to fetch signer assignment document') do
          http_get('sign', signer_access_code: signer_access_code,
                           has_accepted_terms: has_accepted_terms)
        end
      end

      def sign(document_id, assignment_id, items, signer_access_code:)
        doc_id = require_id(document_id, 'Document ID')
        asg_id = require_id(assignment_id, 'Assignment ID')
        body   = require_array(items, 'Assignment items')

        call('Failed to sign assignment') do
          http_post("documents/#{doc_id}/assignments/#{asg_id}",
                    body.map { |item| item.is_a?(Hash) ? body_params(item) : item },
                    signer_access_code: signer_access_code)
        end
      end

      def decline(document_id, assignment_id, decline_reason:, signer_access_code:)
        doc_id = require_id(document_id, 'Document ID')
        asg_id = require_id(assignment_id, 'Assignment ID')
        reason = require_id(decline_reason, 'Decline reason')

        call('Failed to decline assignment') do
          http_put("documents/#{doc_id}/assignments/#{asg_id}/reject",
                   body_params(decline_reason: reason),
                   signer_access_code: signer_access_code)
        end
      end

      def whatsapp_notifications(document_id, assignment_id)
        doc_id = require_id(document_id, 'Document ID')
        asg_id = require_id(assignment_id, 'Assignment ID')

        call('Failed to list WhatsApp notifications') do
          http_get("documents/#{doc_id}/assignments/#{asg_id}/whatsapp-notifications")
        end
      end
    end
  end
end
