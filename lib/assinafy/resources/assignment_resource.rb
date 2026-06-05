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
        # - `signers: [{ id:, verification_method:, notification_methods:, step: }]`
        # - Legacy `signer_ids:`/`signerIds:` arrays of IDs
        #
        # @param payload [Hash]
        # @param options [Hash]
        # @option options [Boolean] :allow_signers_without_id allow estimate-cost
        #   payloads where method-only signer descriptors carry no id
        # @return [Hash] string-keyed body suitable for {#create} / {#estimate_cost}
        # @raise [Assinafy::ValidationError] on missing required fields
        # @example Bare signer IDs are normalised into { id: } hashes (virtual method)
        #   Assinafy::Resources::AssignmentResource.build_payload(signers: %w[s1 s2])
        #   # => { "method" => "virtual", "signers" => [{ "id" => "s1" }, { "id" => "s2" }] }
        # @example Rich signer descriptors with sequential signing steps and optional fields
        #   Assinafy::Resources::AssignmentResource.build_payload(
        #     signers:        [{ id: "s1", verification_method: "Email", notification_methods: ["Email"], step: 1 }],
        #     message:        "Please sign",
        #     expires_at:     "2026-12-31T23:59:00Z",
        #     copy_receivers: ["cc@example.com"]
        #   )
        #   # => {
        #   #   "method"     => "virtual",
        #   #   "signers"    => [{ "id" => "s1", "verification_method" => "Email",
        #   #                      "notification_methods" => ["Email"], "step" => 1 }],
        #   #   "message"    => "Please sign", "expires_at" => "2026-12-31T23:59:00Z",
        #   #   "copy_receivers" => ["cc@example.com"]
        #   # }
        # @example Estimate-cost payload — method-only descriptor with no id (allow flag set)
        #   Assinafy::Resources::AssignmentResource.build_payload(
        #     { signers: [{ verification_method: "Whatsapp" }] }, { allow_signers_without_id: true }
        #   )
        #   # => { "method" => "virtual", "signers" => [{ "verification_method" => "Whatsapp" }] }
        # @example Collect method — positioned-field entries instead of bare signers
        #   Assinafy::Resources::AssignmentResource.build_payload(
        #     method: "collect", entries: [{ page_id: "p1", fields: [] }]
        #   )
        #   # => { "method" => "collect", "entries" => [{ "page_id" => "p1", "fields" => [] }] }
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
          normalised[:step]                 = r[:step]                  unless r[:step].nil?

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
      # @return [Hash] the assignment object (resource, id, method, expires_at, message, signers[],
      #   items[], summary{signer_count, completed_count, signers[]}, signing_urls[], copy_receivers[])
      # @see POST /documents/{documentId}/assignments
      # @example Create a virtual assignment for one signer
      #   resource.create("1032009d72b364f377ff270405cc", signers: %w[19e6b92e7895332ed9708535d8c],
      #                   message: "SDK audit E2E - please ignore")
      #   # Request body the SDK sends:
      #   # { "method" => "virtual", "signers" => [{ "id" => "19e6b92e7895332ed9708535d8c" }],
      #   #   "message" => "SDK audit E2E - please ignore" }
      #   # => {
      #   #   "resource" => "assignment", "id" => "19e99aa0633e32ac13f845c08db",
      #   #   "sender_email" => "bill@febacapital.com", "method" => "virtual",
      #   #   "expires_at" => nil, "message" => "SDK audit E2E - please ignore",
      #   #   "signers" => [{ "id" => "19e6b92e7895332ed9708535d8c", "full_name" => "Audit Bill A2",
      #   #     "email" => "bill@febacapital.com", "whatsapp_phone_number" => nil,
      #   #     "has_accepted_terms" => false, "completed" => false, "notification_history" => [],
      #   #     "verification_method" => "Email", "notification_methods" => ["Email"],
      #   #     "step" => 1, "notified" => true }],
      #   #   "copy_receivers" => [],
      #   #   "items" => [{ "id" => "103200a43e372db16f48a6f0f2d4", "page" => nil,
      #   #     "signer" => { "id" => "19e6b92e7895332ed9708535d8c", ... },
      #   #     "field" => { "id" => "102d25a48bc7357b93f9b8e01b24", "name" => "Virtual",
      #   #       "type" => "virtual", "is_pre_defined" => true, ... },
      #   #     "display_settings" => [], "value" => nil, "completed" => false }],
      #   #   "summary" => { "signer_count" => 1, "completed_count" => 0, "signers" => [{ ... }] },
      #   #   "signing_urls" => [{ "signer_id" => "19e6b92e7895332ed9708535d8c",
      #   #     "url" => "https://app-sandbox.assinafy.com.br/sign/103200a3...?email=bill%40febacapital.com" }]
      #   # } # ... (see docs for full shape)
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
      # @return [Hash] cost breakdown (documents, credits, needs_extra_document, extra_document_cost,
      #   total_credits, breakdown[], document_balance, credit_balance, has_sufficient_resources,
      #   blocking_reason, message)
      # @see POST /documents/{documentId}/assignments/estimate-cost
      # @example Estimate cost of inviting a WhatsApp signer (no id needed)
      #   resource.estimate_cost("1032009d72b364f377ff270405cc",
      #                          signers: [{ verification_method: "Whatsapp" }])
      #   # Request body the SDK sends:
      #   # { "method" => "virtual", "signers" => [{ "verification_method" => "Whatsapp" }] }
      #   # => {
      #   #   "documents" => 1, "credits" => 0, "needs_extra_document" => false,
      #   #   "extra_document_cost" => 0, "total_credits" => 0, "breakdown" => [],
      #   #   "document_balance" => 62, "credit_balance" => 0,
      #   #   "has_sufficient_resources" => true, "blocking_reason" => nil, "message" => nil
      #   # }
      def estimate_cost(document_id, payload)
        doc_id = require_id(document_id, 'Document ID')
        body   = self.class.build_payload(payload, allow_signers_without_id: true)

        call('Failed to estimate assignment cost') do
          http_post("documents/#{doc_id}/assignments/estimate-cost", body)
        end
      end

      # Update the expiration timestamp of an existing assignment. The
      # `expires_at` body field is required by the API and accepts an explicit
      # `nil` (serialized as JSON `null`) to mean "no expiration". The value is
      # therefore sent verbatim rather than through {Utils.body_params}, which
      # would drop the nil.
      #
      # @param document_id   [String]
      # @param assignment_id [String]
      # @param expires_at    [String, nil] ISO 8601 timestamp, or nil for no expiry
      # @return [Hash] the updated assignment object (same shape as {#create}; expires_at reflects
      #   the new value — nil when cleared)
      # @see PUT /documents/{documentId}/assignments/{assignmentId}/reset-expiration
      # @example Set a new expiration timestamp
      #   resource.reset_expiration("1032009d72b364f377ff270405cc", "19e99aa0633e32ac13f845c08db",
      #                             "2026-12-31T23:59:00Z")
      #   # Request body the SDK sends: { "expires_at" => "2026-12-31T23:59:00Z" }
      #   # => { "resource" => "assignment", "id" => "19e99aa0633e32ac13f845c08db",
      #   #      "method" => "virtual", "expires_at" => "2026-12-31T23:59:00Z",
      #   #      "signers" => [{ ... }], "items" => [{ ... }], "summary" => { ... },
      #   #      "signing_urls" => [{ ... }], "copy_receivers" => [] } # ... (see docs for full shape)
      # @example Clear the expiration (nil is sent verbatim as JSON null)
      #   resource.reset_expiration("1032009d72b364f377ff270405cc", "19e99aa0633e32ac13f845c08db", nil)
      #   # Request body the SDK sends: { "expires_at" => nil }
      #   # => { "resource" => "assignment", "id" => "19e99aa0633e32ac13f845c08db",
      #   #      "method" => "virtual", "expires_at" => nil, ... } # ... (see docs for full shape)
      def reset_expiration(document_id, assignment_id, expires_at)
        doc_id = require_id(document_id, 'Document ID')
        asg_id = require_id(assignment_id, 'Assignment ID')

        call('Failed to update assignment expiration') do
          http_put("documents/#{doc_id}/assignments/#{asg_id}/reset-expiration",
                   { 'expires_at' => expires_at })
        end
      end

      # Resend the assignment notification (email/WhatsApp) to a signer.
      # May charge credits — use {#estimate_resend_cost} to preview.
      #
      # @param document_id   [String]
      # @param assignment_id [String]
      # @param signer_id     [String]
      # @return [Hash] delivery confirmation (is_sent, document_id, signer_id)
      # @see PUT /documents/{documentId}/assignments/{assignmentId}/signers/{signerId}/resend
      # @example Resend the signing notification to a signer
      #   resource.resend_notification("c57d51eaad68a7", "d51edaee68a7", "a51edaee68a7")
      #   # (no request body)
      #   # => { "is_sent" => true, "document_id" => "c57d51eaad68a7", "signer_id" => "a51edaee68a7" }
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
      # @return [Hash] cost breakdown (total, breakdown[]{code, name, cost}, credit_balance,
      #   has_sufficient_credits)
      # @see POST /documents/{documentId}/assignments/{assignmentId}/signers/{signerId}/estimate-resend-cost
      # @example Preview the cost of resending to a WhatsApp signer (0.2 credits)
      #   resource.estimate_resend_cost("60f720572d7fecf7c16c8463", "61f720572d7fecf7c16c8464",
      #                                 "615605f50e968054a5b7c9b8")
      #   # (no request body)
      #   # => {
      #   #   "total" => 0.2,
      #   #   "breakdown" => [{ "code" => "NotificationWhatsappResend",
      #   #                     "name" => "Whatsapp Notification Resend", "cost" => 0.2 }],
      #   #   "credit_balance" => 100, "has_sufficient_credits" => true
      #   # }
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
      # @return [Hash] the document (id, account_id, name, status, artifacts, signing_url, ...) with an
      #   embedded current_signer and assignment (items filtered to the current signer); no pages array
      # @see GET /sign
      # @example Resolve the document a signer was invited to sign
      #   resource.signer_document(signer_access_code: "9uAWyOXx9hgzCKdCuahkinwvg8tWJ2RC")
      #   # (no request body — signer-access-code is a query param)
      #   # => {
      #   #   "id" => "6981dbd199996981d", "account_id" => "1a", "name" => "my_document.pdf",
      #   #   "status" => "metadata_ready",
      #   #   "artifacts" => { "original" => "https://.../download/original",
      #   #                    "thumbnail" => "https://.../thumbnail" },
      #   #   "is_closed" => false, "signing_url" => "%ui_base_url%/sign/doc1",
      #   #   "decline_reason" => nil, "declined_by" => nil,
      #   #   "current_signer" => { "id" => "62d6ee35c7741ca4006b9e11", "full_name" => "Signer Name",
      #   #     "email" => "signer@example.com", "has_accepted_terms" => false,
      #   #     "verification_method" => "Email", "notification_methods" => ["Email"] },
      #   #   "assignment" => { "id" => "1", "method" => "virtual", "expires_at" => nil,
      #   #     "items" => [{ "id" => "dbd199996981d", "field" => { "type" => "virtual" }, ... }] }
      #   # } # ... (see docs for full shape)
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
      # @return [Array] empty array on success (the API returns no payload)
      # @see POST /documents/{documentId}/assignments/{assignmentId}
      # @example Sign with snake_case keys — mapped to camelCase itemId/fieldId/pageId
      #   resource.sign("c57d51eaad68a7", "d51edaee68a7",
      #     [{ item_id: "615606efcde1a39c9d21e30e", field_id: "6152120297080d55bdd13197",
      #        page_id: "615213ed81b071f4293b2fc2", value: "Signed by Sonny Bayer" }],
      #     signer_access_code: "9uAWyOXx9hgzCKdCuahkinwvg8tWJ2RC")
      #   # Request body the SDK sends (snake_case keys mapped to camelCase):
      #   # [{ "itemId" => "615606efcde1a39c9d21e30e", "fieldId" => "6152120297080d55bdd13197",
      #   #    "pageId" => "615213ed81b071f4293b2fc2", "value" => "Signed by Sonny Bayer" }]
      #   # => []
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
      # @return [Array] empty array on success (the API returns no payload)
      # @see PUT /documents/{documentId}/assignments/{assignmentId}/reject
      # @example Decline an assignment as the signer
      #   resource.decline("c57d51eaad68a7", "d51edaee68a7",
      #                    decline_reason: "I do not agree with clause 2.",
      #                    signer_access_code: "1e7d51e68a7")
      #   # Request body the SDK sends: { "decline_reason" => "I do not agree with clause 2." }
      #   # => []
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
      # @return [Array<Hash>] notification objects (sent_at, header, body, buttons[]{text}, phone_number,
      #   signer_id); empty array when no WhatsApp notifications were sent
      # @see GET /documents/{documentId}/assignments/{assignmentId}/whatsapp-notifications
      # @example List WhatsApp notifications sent for an assignment
      #   resource.whatsapp_notifications("c57d51eaad68a7", "d51edaee68a7")
      #   # (no request body)
      #   # => [
      #   #   { "sent_at" => 1710000000,
      #   #     "header" => "Documento para assinatura: Contrato de Servico",
      #   #     "body" => "Oi, Maria.\n\nJoao Silva enviou um documento...",
      #   #     "buttons" => [{ "text" => "Abrir documento" }],
      #   #     "phone_number" => "+5511999990001", "signer_id" => "a51edaee68a7" }
      #   # ]
      #   # => [] # when no WhatsApp notifications were sent (e.g. email-only assignment)
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
