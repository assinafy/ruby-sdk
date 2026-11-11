# frozen_string_literal: true

module Assinafy
  module Resources
    # Groups documents into one invitation while retaining each document's signatures and artifacts.
    class EnvelopeResource < BaseResource
      # @param params [Hash] search, status (open/closed), page, per_page
      # @param account_id_override [String, nil]
      # @return [Hash] paginated DocumentEnvelope objects
      # @raise [ValidationError] on invalid filters or account ID
      # @raise [ApiError, NetworkError] on API or transport failure
      # @see GET /accounts/{accountId}/envelopes
      # @example
      #   client.envelopes.list(status: 'open') # GET .../envelopes?status=open; no body
      #   # => { data: [{ 'id' => 'envelope-id', 'name' => 'Contract', 'documents' => [],
      #   #      'message' => nil, 'counts' => nil, 'signing_urls' => [], 'created_at' => '2026-11-11T12:00:00Z' }] }
      def list(params = {}, account_id_override = nil)
        query = query_params(params)
        if query.key?('status') && !%w[open closed].include?(query['status'])
          raise ValidationError.new('status must be open or closed')
        end
        if query.key?('search') && !query['search'].is_a?(String)
          raise ValidationError.new('search must be a String')
        end

        call_list('Failed to list envelopes') { http_get(envelopes_path(account_id_override), query) }
      end

      # @param payload [Hash] EnvelopeCreateRequest: name, signers, documents, optional message/max_total_credits
      # @param account_id_override [String, nil]
      # @param idempotency_key [String, nil] reuse after a lost response to avoid creating or charging twice
      # @return [Hash] DocumentEnvelope; notification failure does not undo creation
      # @raise [ValidationError] on invalid payload, key or IDs
      # @raise [ApiError, NetworkError] on API or transport failure
      # @see POST /accounts/{accountId}/envelopes
      # @example
      #   client.envelopes.create({ name: 'Contract', signers: [{ id: 'signer-id' }],
      #     documents: [{ id: 'document-id', signer_ids: ['signer-id'] }] }, idempotency_key: 'request-id')
      #   # POST body: { "name": "Contract", "signers": [{ "id": "signer-id" }],
      #   #   "documents": [{ "id": "document-id", "signer_ids": ["signer-id"] }] }
      #   # => { 'resource' => 'envelope', 'id' => 'envelope-id', 'name' => 'Contract', 'message' => nil,
      #   #      'documents' => [{ 'id' => 'document-id', 'position' => 1, 'name' => 'contract.pdf',
      #   #        'status' => 'pending_signature', 'artifacts' => {}, 'signers' => [] }],
      #   #      'counts' => { 'pending_signature' => 1 }, 'signing_urls' => [],
      #   #      'created_at' => '2026-11-11T12:00:00Z' }
      def create(payload, account_id_override = nil, idempotency_key: nil)
        body = create_payload(payload)
        path = envelopes_path(account_id_override)
        headers = idempotency_headers(idempotency_key)
        call('Failed to create envelope') { http_post(path, body, headers: headers) }
      end

      # @param payload [Hash] the same EnvelopeCreateRequest as create
      # @param account_id_override [String, nil]
      # @return [Hash] CostEstimate; creates and charges nothing
      # @raise [ValidationError] on invalid payload or IDs
      # @raise [ApiError, NetworkError] on API or transport failure
      # @see POST /accounts/{accountId}/envelopes/estimate-cost
      # @example
      #   client.envelopes.estimate_cost(name: 'Contract', signers: [{ id: 'signer-id' }],
      #     documents: [{ id: 'document-id', signer_ids: ['signer-id'] }])
      #   # POST body: { "name": "Contract", "signers": [{ "id": "signer-id" }],
      #   #   "documents": [{ "id": "document-id", "signer_ids": ["signer-id"] }] }
      #   # => { 'total_credits' => 0, 'has_sufficient_resources' => true, 'breakdown' => [] }
      def estimate_cost(payload, account_id_override = nil)
        body = create_payload(payload)
        path = "#{envelopes_path(account_id_override)}/estimate-cost"
        call('Failed to estimate envelope cost') { http_post(path, body) }
      end

      # @param envelope_id [String]
      # @param account_id_override [String, nil]
      # @return [Hash] DocumentEnvelope (see create for its complete shape)
      # @raise [ValidationError] on invalid IDs
      # @raise [ApiError, NetworkError] on API or transport failure
      # @see GET /accounts/{accountId}/envelopes/{envelopeId}
      # @example
      #   client.envelopes.get('envelope-id') # GET .../envelopes/envelope-id; no body
      #   # => { 'id' => 'envelope-id', 'name' => 'Contract', 'message' => nil, 'documents' => [],
      #   #      'counts' => nil, 'signing_urls' => [], 'created_at' => '2026-11-11T12:00:00Z' }
      def get(envelope_id, account_id_override = nil)
        path = envelope_path(envelope_id, account_id_override)
        call('Failed to get envelope') { http_get(path) }
      end

      # @param envelope_id [String]
      # @param payload [Hash] name, message (nil clears), document_ids in desired order
      # @param account_id_override [String, nil]
      # @return [Hash] updated DocumentEnvelope
      # @raise [ValidationError] on invalid payload or IDs
      # @raise [ApiError, NetworkError] on API or transport failure
      # @see PATCH /accounts/{accountId}/envelopes/{envelopeId}
      # @example
      #   client.envelopes.update('envelope-id', message: nil)
      #   # PATCH body: { "message": null }
      #   # => { 'id' => 'envelope-id', 'name' => 'Contract', 'message' => nil, 'documents' => [],
      #   #      'counts' => nil, 'signing_urls' => [], 'created_at' => '2026-11-11T12:00:00Z' }
      def update(envelope_id, payload, account_id_override = nil)
        body = require_payload(payload).transform_keys(&:to_s)
        require_keys!(body, %w[name message document_ids])
        validate_name!(body['name']) if body.key?('name')
        validate_message!(body['message'])
        unique_ids!(body['document_ids'], 'document_ids') if body.key?('document_ids')
        path = envelope_path(envelope_id, account_id_override)
        call('Failed to update envelope') { http_patch(path, body) }
      end

      # @param envelope_id [String]
      # @param account_id_override [String, nil]
      # @return [nil] deletes only the closed envelope; its documents remain
      # @raise [ValidationError] on invalid IDs
      # @raise [ApiError, NetworkError] on API or transport failure (409 while open)
      # @see DELETE /accounts/{accountId}/envelopes/{envelopeId}
      # @example
      #   client.envelopes.delete('envelope-id') # DELETE .../envelopes/envelope-id; no body
      #   # => nil
      def delete(envelope_id, account_id_override = nil)
        path = envelope_path(envelope_id, account_id_override)
        call_void('Failed to delete envelope') { http_delete(path) }
      end

      # @param envelope_id [String]
      # @param params [Hash] sort, page, per_page
      # @param account_id_override [String, nil]
      # @return [Hash] paginated EnvelopeActivity objects
      # @raise [ValidationError] on invalid IDs or query shape
      # @raise [ApiError, NetworkError] on API or transport failure
      # @see GET /accounts/{accountId}/envelopes/{envelopeId}/activities
      # @example
      #   client.envelopes.activities('envelope-id', per_page: 20)
      #   # GET .../envelopes/envelope-id/activities?per-page=20; no body
      #   # => { data: [{ 'document_id' => 'document-id', 'document_name' => 'contract.pdf',
      #   #      'event' => 'signature_requested', 'created_at' => '2026-11-11T12:00:00Z' }] }
      def activities(envelope_id, params = {}, account_id_override = nil)
        path = "#{envelope_path(envelope_id, account_id_override)}/activities"
        query = query_params(params)
        call_list('Failed to list envelope activities') { http_get(path, query) }
      end

      # @param envelope_id [String]
      # @param artifact [String] original, certificated, certificate-page, pades or bundle
      # @param account_id_override [String, nil]
      # @return [String] binary ZIP of available document artifacts in envelope order
      # @raise [ValidationError] on invalid IDs or artifact
      # @raise [ApiError, NetworkError] on API or transport failure (404 if no artifact exists)
      # @see GET /accounts/{accountId}/envelopes/{envelopeId}/download/{artifactName}
      # @example
      #   client.envelopes.download('envelope-id', 'original')
      #   # GET .../envelopes/envelope-id/download/original; no body; => binary ZIP bytes
      def download(envelope_id, artifact = 'certificated', account_id_override = nil)
        unless DocumentResource::ARTIFACT_TYPES.include?(artifact)
          raise ValidationError.new("artifact must be one of: #{DocumentResource::ARTIFACT_TYPES.join(', ')}")
        end

        path = "#{envelope_path(envelope_id, account_id_override)}/download/#{artifact}"
        call_binary('Failed to download envelope') { http_get(path) }
      end

      # @param envelope_id [String]
      # @param account_id_override [String, nil]
      # @return [Array<Hash>] each document's id, status and cancelled flag; repeatable
      # @raise [ValidationError] on invalid IDs
      # @raise [ApiError, NetworkError] on API or transport failure
      # @see PUT /accounts/{accountId}/envelopes/{envelopeId}/cancel
      # @example
      #   client.envelopes.cancel('envelope-id') # PUT .../envelopes/envelope-id/cancel; no body
      #   # => [{ 'id' => 'document-id', 'status' => 'rejected_by_user', 'cancelled' => true }]
      def cancel(envelope_id, account_id_override = nil)
        path = "#{envelope_path(envelope_id, account_id_override)}/cancel"
        call_array('Failed to cancel envelope') { http_put(path) }
      end

      # @param envelope_id [String]
      # @param signer_id [String]
      # @param account_id_override [String, nil]
      # @return [Hash] is_sent, envelope_id, signer_id; paid notifications are charged
      # @raise [ValidationError] on invalid IDs
      # @raise [ApiError, NetworkError] on API or transport failure
      # @see PUT /accounts/{accountId}/envelopes/{envelopeId}/signers/{signerId}/resend
      # @example
      #   client.envelopes.resend_notification('envelope-id', 'signer-id')
      #   # PUT .../envelopes/envelope-id/signers/signer-id/resend; no body
      #   # => { 'is_sent' => true, 'envelope_id' => 'envelope-id', 'signer_id' => 'signer-id' }
      def resend_notification(envelope_id, signer_id, account_id_override = nil)
        sid = require_id(signer_id, 'Signer ID')
        path = "#{envelope_path(envelope_id, account_id_override)}/signers/#{sid}/resend"
        call('Failed to resend envelope invitation') { http_put(path) }
      end

      # @param envelope_id [String]
      # @param payload [Hash] EnvelopeDocumentRequest plus optional max_total_credits
      # @param account_id_override [String, nil]
      # @return [Hash] DocumentEnvelope; notifies the chosen existing envelope signers
      # @raise [ValidationError] on invalid payload or IDs
      # @raise [ApiError, NetworkError] on API or transport failure
      # @see POST /accounts/{accountId}/envelopes/{envelopeId}/documents
      # @example
      #   client.envelopes.add_document('envelope-id', id: 'document-id', signer_ids: ['signer-id'])
      #   # POST body: { "id": "document-id", "signer_ids": ["signer-id"] }
      #   # => DocumentEnvelope, as returned by create, with the document appended
      def add_document(envelope_id, payload, account_id_override = nil)
        body = document_payload(payload)
        path = "#{envelope_path(envelope_id, account_id_override)}/documents"
        call('Failed to add envelope document') { http_post(path, body) }
      end

      # @param envelope_id [String]
      # @param document_id [String]
      # @param account_id_override [String, nil]
      # @return [Hash] DocumentEnvelope; removes and cancels the open document, notifying its recipients
      # @raise [ValidationError] on invalid IDs
      # @raise [ApiError, NetworkError] on API or transport failure (409 if document is closed)
      # @see DELETE /accounts/{accountId}/envelopes/{envelopeId}/documents/{documentId}
      # @example
      #   client.envelopes.remove_document('envelope-id', 'document-id')
      #   # DELETE .../envelopes/envelope-id/documents/document-id; no body
      #   # => { 'id' => 'envelope-id', 'name' => 'Contract', 'message' => nil, 'documents' => [],
      #   #      'counts' => nil, 'signing_urls' => [], 'created_at' => '2026-11-11T12:00:00Z' }
      def remove_document(envelope_id, document_id, account_id_override = nil)
        id = require_id(document_id, 'Document ID')
        path = "#{envelope_path(envelope_id, account_id_override)}/documents/#{id}"
        call('Failed to remove envelope document') { http_delete(path) }
      end

      private

      def envelopes_path(override)
        "accounts/#{account_id(override)}/envelopes"
      end

      def envelope_path(envelope_id, override)
        "#{envelopes_path(override)}/#{require_id(envelope_id, 'Envelope ID')}"
      end

      def require_keys!(body, allowed)
        if body.empty? || (body.keys - allowed).any?
          raise ValidationError.new("Provide only envelope fields: #{allowed.join(', ')}")
        end
      end

      def validate_name!(name)
        require_string(name, 'Name', max_length: 255)
        raise ValidationError.new('Name cannot contain <') if name.include?('<')
      end

      def validate_message!(message)
        raise ValidationError.new('message must be a String or nil') unless message.nil? || message.is_a?(String)
      end

      def unique_ids!(ids, label)
        require_array(ids, label).each { |id| require_id(id, label) }
        raise ValidationError.new("#{label} must not contain duplicates") unless ids.uniq == ids

        ids
      end

      def create_payload(payload)
        body = body_params(require_payload(payload))
        require_keys!(body, %w[name message max_total_credits signers documents])
        validate_name!(body['name'])
        validate_message!(body['message'])
        Utils.require_credit_ceiling(body['max_total_credits'])
        body['signers'] = bounded_items(body['signers'], 'signers').map { |signer| envelope_signer(signer) }
        body['documents'] = bounded_items(body['documents'], 'documents').map do |document|
          document_payload(document, body['signers'])
        end
        validate_membership!(body)
        body
      end

      def validate_membership!(body)
        ids = unique_ids!(body['signers'].map { |signer| signer['id'] }, 'signers')
        unique_ids!(body['documents'].map { |document| document['id'] }, 'documents')
        used = body['documents'].flat_map { |document| document['signer_ids'] }.uniq
        raise ValidationError.new('Every envelope signer must be on a document') unless used.sort == ids.sort
      end

      def bounded_items(value, label)
        items = require_array(value, label)
        raise ValidationError.new("An envelope supports at most 20 #{label}") if items.length > 20

        items
      end

      def envelope_signer(signer)
        require_payload(signer, 'Envelope signer')
        require_keys!(signer, %w[id verification_method notification_methods embedded])
        require_id(signer['id'], 'Signer ID')
        AssignmentResource.build_payload(signers: [signer]).fetch('signers').first
      end

      def document_payload(payload, signers = nil)
        body = body_params(require_payload(payload, 'Envelope document'))
        allowed = %w[id method entries signer_ids expires_at copy_receiver_ids]
        allowed << 'max_total_credits' unless signers
        require_keys!(body, allowed)
        require_id(body['id'], 'Document ID')
        ids = unique_ids!(body['signer_ids'], 'signer_ids')
        selected = signers ? signers.select { |signer| ids.include?(signer['id']) } : ids
        if signers && selected.length != ids.length
          raise ValidationError.new('Document signers must belong to the envelope')
        end

        AssignmentResource.build_payload(method: body.fetch('method', 'virtual'), signers: selected,
                                         entries: body['entries'], expires_at: body['expires_at'],
                                         copy_receivers: body['copy_receiver_ids'])
        Utils.require_credit_ceiling(body['max_total_credits'])
        body
      end
    end
  end
end
