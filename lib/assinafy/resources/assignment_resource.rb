# frozen_string_literal: true

module Assinafy
  module Resources
    # Assignments — invitations to sign a specific document. Covers virtual
    # (no positioned fields) and collect (positioned fields) methods, cost
    # estimation, signer notification resends, declines, and signing.
    #
    # See https://api.assinafy.com.br/v1/docs#assignment for the full
    # documentation of these endpoints.
    class AssignmentResource < BaseResource
      OPTIONAL_FIELDS   = %i[message expires_at copy_receivers].freeze
      SIGN_ITEM_KEY_MAP = {
        'item_id'  => 'itemId',
        'field_id' => 'fieldId',
        'page_id'  => 'pageId',
        'value'    => 'value'
      }.freeze

      class << self
        # Normalise a flexible Ruby-side assignment payload into the body
        # shape the API expects. Accepts:
        #
        # - `signers: ['id1', 'id2']` — bare IDs
        # - `signers: [{ id:, verification_method:, notification_methods: }]`
        # - Legacy `signer_ids:`/`signerIds:` arrays of IDs
        #
        # @param payload [Hash]
        # @param options [Hash]
        # @option options [Boolean] :allow_signers_without_id allow estimate-cost
        #   payloads where method-only signer descriptors carry no id
        # @return [Hash] string-keyed body suitable for {#create} / {#estimate_cost}
        # @raise [Assinafy::ValidationError] on missing required fields
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

      # Create an assignment for a document. See {.build_payload} for the
      # accepted shapes.
      #
      # @param document_id [String]
      # @param payload     [Hash]
      # @return [Hash] assignment object
      # @see POST /documents/{documentId}/assignments
      def create(document_id, payload)
        doc_id = require_id(document_id, 'Document ID')
        body   = self.class.build_payload(payload)

        @logger.info("Creating assignment for document #{doc_id}")

        call('Failed to create assignment') do
          http_post("documents/#{doc_id}/assignments", body)
        end
      end

      # Estimate the credit cost of a potential assignment, without creating it.
      # Accepts the same payload as {#create}, but signer descriptors may omit
      # `id` when only `verification_method`/`notification_methods` are needed.
      #
      # @param document_id [String]
      # @param payload     [Hash]
      # @return [Hash] cost breakdown
      # @see POST /documents/{documentId}/assignments/estimate-cost
      def estimate_cost(document_id, payload)
        doc_id = require_id(document_id, 'Document ID')
        body   = self.class.build_payload(payload, allow_signers_without_id: true)

        call('Failed to estimate assignment cost') do
          http_post("documents/#{doc_id}/assignments/estimate-cost", body)
        end
      end

      # Update the expiration timestamp of an existing assignment.
      #
      # @param document_id   [String]
      # @param assignment_id [String]
      # @param expires_at    [String] ISO 8601 timestamp
      # @return [Hash]
      # @see PUT /documents/{documentId}/assignments/{assignmentId}/reset-expiration
      def reset_expiration(document_id, assignment_id, expires_at)
        doc_id = require_id(document_id, 'Document ID')
        asg_id = require_id(assignment_id, 'Assignment ID')

        call('Failed to update assignment expiration') do
          http_put("documents/#{doc_id}/assignments/#{asg_id}/reset-expiration",
                   body_params(expires_at: expires_at))
        end
      end

      # Resend the assignment notification (email/WhatsApp) to a signer.
      # May charge credits — use {#estimate_resend_cost} to preview.
      #
      # @param document_id   [String]
      # @param assignment_id [String]
      # @param signer_id     [String]
      # @return [Hash]
      # @see PUT /documents/{documentId}/assignments/{assignmentId}/signers/{signerId}/resend
      def resend_notification(document_id, assignment_id, signer_id)
        doc_id = require_id(document_id, 'Document ID')
        asg_id = require_id(assignment_id, 'Assignment ID')
        sid    = require_id(signer_id, 'Signer ID')

        call('Failed to resend signer notification') do
          http_put("documents/#{doc_id}/assignments/#{asg_id}/signers/#{sid}/resend")
        end
      end

      # Estimate the credit cost of resending the notification to a signer.
      #
      # @param document_id   [String]
      # @param assignment_id [String]
      # @param signer_id     [String]
      # @return [Hash] cost breakdown
      # @see POST /documents/{documentId}/assignments/{assignmentId}/signers/{signerId}/estimate-resend-cost
      def estimate_resend_cost(document_id, assignment_id, signer_id)
        doc_id = require_id(document_id, 'Document ID')
        asg_id = require_id(assignment_id, 'Assignment ID')
        sid    = require_id(signer_id, 'Signer ID')

        call('Failed to estimate resend cost') do
          http_post("documents/#{doc_id}/assignments/#{asg_id}/signers/#{sid}/estimate-resend-cost")
        end
      end

      # Fetch the document a signer is being asked to sign (signer-access-code auth).
      #
      # @param signer_access_code  [String]
      # @param has_accepted_terms  [Boolean, nil]
      # @return [Hash]
      # @see GET /sign
      def signer_document(signer_access_code:, has_accepted_terms: nil)
        call('Failed to fetch signer assignment document') do
          http_get('sign', signer_access_code: signer_access_code,
                           has_accepted_terms: has_accepted_terms)
        end
      end

      # Submit signatures for an assignment as a signer.
      #
      # The API uses camelCase for this body. Callers may pass snake_case
      # (`item_id`, `field_id`, `page_id`, `value`) — this method maps them
      # to the API's `itemId`, `fieldId`, `pageId`, `value`.
      #
      # @param document_id        [String]
      # @param assignment_id      [String]
      # @param items              [Array<Hash>]
      # @param signer_access_code [String]
      # @return [Hash]
      # @see POST /documents/{documentId}/assignments/{assignmentId}
      def sign(document_id, assignment_id, items, signer_access_code:)
        doc_id = require_id(document_id, 'Document ID')
        asg_id = require_id(assignment_id, 'Assignment ID')
        body   = require_array(items, 'Assignment items').map { |item| normalise_sign_item(item) }

        call('Failed to sign assignment') do
          http_post("documents/#{doc_id}/assignments/#{asg_id}", body,
                    signer_access_code: signer_access_code)
        end
      end

      # Decline an assignment as a signer.
      #
      # @param document_id        [String]
      # @param assignment_id      [String]
      # @param decline_reason     [String]
      # @param signer_access_code [String]
      # @return [Hash]
      # @see PUT /documents/{documentId}/assignments/{assignmentId}/reject
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

      # List the WhatsApp notifications that were sent for an assignment,
      # including the rendered template text.
      #
      # @param document_id   [String]
      # @param assignment_id [String]
      # @return [Array<Hash>]
      # @see GET /documents/{documentId}/assignments/{assignmentId}/whatsapp-notifications
      def whatsapp_notifications(document_id, assignment_id)
        doc_id = require_id(document_id, 'Document ID')
        asg_id = require_id(assignment_id, 'Assignment ID')

        call('Failed to list WhatsApp notifications') do
          http_get("documents/#{doc_id}/assignments/#{asg_id}/whatsapp-notifications")
        end
      end

      private

      def normalise_sign_item(item)
        return item unless item.is_a?(Hash)

        item.each_with_object({}) do |(key, value), result|
          raw = key.to_s
          result[SIGN_ITEM_KEY_MAP.fetch(raw, raw)] = value
        end
      end
    end
  end
end
