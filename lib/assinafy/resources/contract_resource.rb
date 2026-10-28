# frozen_string_literal: true

module Assinafy
  module Resources
    # Contract terms tracked on workspace documents, including amendments,
    # renewals, terminations, and lifecycle queries.
    class ContractResource < BaseResource
      STATUSES       = %w[draft active expired terminated].freeze
      RELATION_TYPES = %w[amendment renewal termination].freeze
      SORTS           = %w[end_date -end_date updated_at -updated_at].freeze
      LIST_FIELDS     = %w[
        status counterparty search end_date_from end_date_to ending_within_days
        external_system external_id sort expand page per-page
      ].freeze
      UPDATE_FIELDS = %w[
        status counterparty_name counterparty_taxpayer_id value currency start_date end_date
        auto_renew renewal_term_months notice_period_days owner_id metadata external_references
        parent_document_id relation_type updated_at
      ].freeze
      RENEW_FIELDS     = %w[end_date value term updated_at].freeze
      TERMINATE_FIELDS = %w[reason updated_at].freeze

      # List tracked contracts in a workspace, most recently updated first.
      #
      # @param params [Hash] optional filters: `status`, `counterparty`, `search`,
      #   `end_date_from`, `end_date_to`, `ending_within_days`, `external_system`,
      #   `external_id`, `sort`, `expand`, `page`, and `per_page`
      # @param account_id_override [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [...], meta: { ... } }`
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid filters or account ID
      # @see GET /accounts/{accountId}/contracts
      # @example List active contracts ending in the next 30 days
      #   client.contracts.list(status: ['active'], ending_within_days: 30, expand: 'document')
      #   # Request: GET /accounts/{accountId}/contracts?status=active&ending_within_days=30&expand=document
      #   # => {
      #   #   data: [{
      #   #     'resource' => 'document_contract', 'document_id' => 'document-id',
      #   #     'status' => 'active', 'counterparty_name' => 'Example Ltda',
      #   #     'counterparty_taxpayer_id' => '11222333000181', 'value' => 120000.50,
      #   #     'currency' => 'BRL', 'start_date' => '2026-11-01', 'end_date' => '2027-10-31',
      #   #     'auto_renew' => true, 'renewal_term_months' => 12, 'notice_period_days' => 30,
      #   #     'term' => 1, 'owner_id' => 'user-id', 'metadata' => { 'crm_stage' => 'won' },
      #   #     'external_references' => [{ 'system' => 'hubspot', 'id' => '98765' }],
      #   #     'document' => { 'id' => 'document-id', 'name' => 'agreement.pdf', 'status' => 'certificated' },
      #   #     'created_at' => '2026-10-23T12:00:00Z', 'updated_at' => '2026-10-23T12:00:00Z'
      #   #   }],
      #   #   meta: { current_page: 1, per_page: 20, total: 1, last_page: 1 }
      #   # }
      def list(params = {}, account_id_override = nil)
        acc_id = account_id(account_id_override)
        query  = contract_list_params(params)

        call_list('Failed to list contracts') do
          http_get("accounts/#{acc_id}/contracts", query)
        end
      end

      # Fetch the contract terms or pending/applied amendment linked to a document.
      # Returns `nil` when the document has no tracked contract terms.
      #
      # @param document_id [String]
      # @param account_id_override [String, nil]
      # @return [Hash, nil] a DocumentContract or DocumentContractAmendment
      # @raise [Assinafy::ApiError] on an unsuccessful response other than 404
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on an invalid ID
      # @see GET /accounts/{accountId}/documents/{documentId}/contract
      # @example Read a contract and its amendments
      #   client.contracts.get('document-id')
      #   # Request: GET /accounts/{accountId}/documents/document-id/contract
      #   # => {
      #   #   'resource' => 'document_contract', 'document_id' => 'document-id', 'status' => 'active',
      #   #   'counterparty_name' => 'Example Ltda', 'counterparty_taxpayer_id' => '11222333000181',
      #   #   'value' => 130000, 'currency' => 'BRL', 'start_date' => '2026-11-01',
      #   #   'end_date' => '2028-06-30', 'auto_renew' => true, 'renewal_term_months' => 12,
      #   #   'notice_period_days' => 30, 'term' => 2, 'owner_id' => 'user-id',
      #   #   'metadata' => { 'crm_stage' => 'won' },
      #   #   'external_references' => [{ 'system' => 'hubspot', 'id' => '98765' }],
      #   #   'amendments' => [{
      #   #     'resource' => 'document_contract_amendment', 'document_id' => 'amendment-id',
      #   #     'document_name' => 'Amendment 1.pdf', 'parent_document_id' => 'document-id',
      #   #     'relation_type' => 'amendment', 'number' => 1, 'status' => 'applied',
      #   #     'document_status' => 'certificated', 'apply_error' => nil, 'currency' => 'BRL',
      #   #     'terms' => { 'value' => 130000, 'end_date' => '2028-06-30' },
      #   #     'changes' => { 'value' => { 'from' => 120000.50, 'to' => 130000 } },
      #   #     'applied_at' => '2027-05-12T18:20:00Z',
      #   #     'created_at' => '2027-05-10T15:00:00Z', 'updated_at' => '2027-05-12T18:20:00Z'
      #   #   }],
      #   #   'created_at' => '2026-10-23T12:00:00Z', 'updated_at' => '2027-05-12T18:20:00Z'
      #   # }
      def get(document_id, account_id_override = nil)
        call_optional('Failed to fetch contract') do
          http_get(contract_path(document_id, account_id_override))
        end
      end

      # Create or partially update contract terms, or link a document as an
      # amendment, renewal, or termination instrument. Explicit `nil` values
      # are sent as JSON null because the API uses them to clear terms.
      #
      # @param document_id [String]
      # @param payload [Hash] at least one DocumentContractInput property
      # @param account_id_override [String, nil]
      # @return [Hash] the saved DocumentContract or DocumentContractAmendment
      # @raise [Assinafy::ApiError] including 403 without the plan and 409 on a stale `updated_at`
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid IDs or payload fields
      # @see PUT /accounts/{accountId}/documents/{documentId}/contract
      # @example Set a document's contract terms
      #   client.contracts.update(
      #     'document-id', status: 'active', counterparty_name: 'Example Ltda',
      #     value: 120000.50, currency: 'BRL', start_date: '2026-11-01', end_date: '2027-10-31',
      #     auto_renew: true, renewal_term_months: 12, notice_period_days: 30,
      #     metadata: { crm_stage: 'won' },
      #     external_references: [{ system: 'hubspot', id: '98765' }]
      #   )
      #   # Request body:
      #   # { "status":"active", "counterparty_name":"Example Ltda", "value":120000.5,
      #   #   "currency":"BRL", "start_date":"2026-11-01", "end_date":"2027-10-31",
      #   #   "auto_renew":true, "renewal_term_months":12, "notice_period_days":30,
      #   #   "metadata":{"crm_stage":"won"},
      #   #   "external_references":[{"system":"hubspot","id":"98765"}] }
      #   # => { 'resource' => 'document_contract', 'document_id' => 'document-id', 'status' => 'active',
      #   #      'counterparty_name' => 'Example Ltda', 'counterparty_taxpayer_id' => nil,
      #   #      'value' => 120000.50, 'currency' => 'BRL', 'start_date' => '2026-11-01',
      #   #      'end_date' => '2027-10-31', 'auto_renew' => true, 'renewal_term_months' => 12,
      #   #      'notice_period_days' => 30, 'term' => 1, 'owner_id' => nil,
      #   #      'metadata' => { 'crm_stage' => 'won' },
      #   #      'external_references' => [{ 'system' => 'hubspot', 'id' => '98765' }],
      #   #      'created_at' => '2026-10-23T12:00:00Z', 'updated_at' => '2026-10-23T12:00:00Z' }
      # @example Link a signed amendment and preserve nulls
      #   client.contracts.update(
      #     'amendment-id', parent_document_id: 'document-id', relation_type: 'amendment',
      #     value: 130000, counterparty_name: nil
      #   )
      #   # Request body includes "counterparty_name": null.
      def update(document_id, payload, account_id_override = nil)
        body = contract_payload(payload, UPDATE_FIELDS, 'Contract payload')
        raise ValidationError.new('Contract payload must change at least one field') if body.empty?

        validate_contract_input!(body)

        call('Failed to update contract') do
          http_put(contract_path(document_id, account_id_override), body)
        end
      end

      # Fetch the root contract and every related amendment, renewal, and
      # termination document. Returns `nil` when the document has no family.
      #
      # @param document_id [String]
      # @param account_id_override [String, nil]
      # @return [Hash, nil] root DocumentContract with `amendments`
      # @raise [Assinafy::ApiError] on an unsuccessful response other than 404
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on an invalid ID
      # @see GET /accounts/{accountId}/documents/{documentId}/contract/related
      # @example Read a family from one of its amendments
      #   client.contracts.related('amendment-id')
      #   # Request: GET /accounts/{accountId}/documents/amendment-id/contract/related
      #   # => { 'resource' => 'document_contract', 'document_id' => 'document-id', 'status' => 'active',
      #   #      'counterparty_name' => 'Example Ltda', 'counterparty_taxpayer_id' => '11222333000181',
      #   #      'value' => 130000, 'currency' => 'BRL', 'start_date' => '2026-11-01',
      #   #      'end_date' => '2028-06-30', 'auto_renew' => true, 'renewal_term_months' => 12,
      #   #      'notice_period_days' => 30, 'term' => 2, 'owner_id' => 'user-id',
      #   #      'metadata' => nil, 'external_references' => [],
      #   #      'amendments' => [{ 'document_id' => 'amendment-id', 'relation_type' => 'amendment',
      #   #                          'number' => 1, 'status' => 'applied', 'terms' => { 'value' => 130000 } }],
      #   #      'created_at' => '2026-10-23T12:00:00Z', 'updated_at' => '2027-05-12T18:20:00Z' }
      def related(document_id, account_id_override = nil)
        call_optional('Failed to fetch related contracts') do
          http_get("#{contract_path(document_id, account_id_override)}/related")
        end
      end

      # Start the contract's next term. Send the current `term` for an
      # idempotent term-based renewal, or an explicit later `end_date`.
      # Explicit `value: nil` clears the contract value.
      #
      # @param document_id [String]
      # @param payload [Hash] `term` or `end_date`, plus optional `value` and `updated_at`
      # @param account_id_override [String, nil]
      # @return [Hash] the renewed DocumentContract
      # @raise [Assinafy::ApiError] including 403 without the plan and 409 on a stale `updated_at`
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid IDs or payload fields
      # @see POST /accounts/{accountId}/documents/{documentId}/contract/renew
      # @example Renew from the current term
      #   client.contracts.renew('document-id', term: 1, value: 126000)
      #   # Request body: { "term": 1, "value": 126000 }
      #   # => { 'resource' => 'document_contract', 'document_id' => 'document-id', 'status' => 'active',
      #   #      'counterparty_name' => 'Example Ltda', 'counterparty_taxpayer_id' => '11222333000181',
      #   #      'value' => 126000, 'currency' => 'BRL', 'start_date' => '2026-11-01',
      #   #      'end_date' => '2028-10-31', 'auto_renew' => true, 'renewal_term_months' => 12,
      #   #      'notice_period_days' => 30, 'term' => 2, 'owner_id' => 'user-id',
      #   #      'metadata' => nil, 'external_references' => [],
      #   #      'created_at' => '2026-10-23T12:00:00Z', 'updated_at' => '2027-10-15T09:30:00Z' }
      def renew(document_id, payload, account_id_override = nil)
        body = contract_payload(payload, RENEW_FIELDS, 'Contract renewal payload')
        validate_renewal!(body)

        call('Failed to renew contract') do
          http_post("#{contract_path(document_id, account_id_override)}/renew", body)
        end
      end

      # Terminate a contract and stop lifecycle alerts. The optional reason is
      # recorded in the document activity event.
      #
      # @param document_id [String]
      # @param payload [Hash] optional `reason` and optimistic-lock `updated_at`
      # @param account_id_override [String, nil]
      # @return [Hash] the terminated DocumentContract
      # @raise [Assinafy::ApiError] including 403 without the plan and 409 on a stale `updated_at`
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid IDs or payload fields
      # @see POST /accounts/{accountId}/documents/{documentId}/contract/terminate
      # @example Terminate with a reason
      #   client.contracts.terminate('document-id', reason: 'Supplier replaced')
      #   # Request body: { "reason": "Supplier replaced" }
      #   # => { 'resource' => 'document_contract', 'document_id' => 'document-id', 'status' => 'terminated',
      #   #      'counterparty_name' => 'Example Ltda', 'counterparty_taxpayer_id' => '11222333000181',
      #   #      'value' => 120000.50, 'currency' => 'BRL', 'start_date' => '2026-11-01',
      #   #      'end_date' => '2027-10-31', 'auto_renew' => true, 'renewal_term_months' => 12,
      #   #      'notice_period_days' => 30, 'term' => 1, 'owner_id' => 'user-id',
      #   #      'metadata' => nil, 'external_references' => [],
      #   #      'created_at' => '2026-10-23T12:00:00Z', 'updated_at' => '2027-03-02T14:00:00Z' }
      def terminate(document_id, payload = {}, account_id_override = nil)
        body = contract_payload(payload, TERMINATE_FIELDS, 'Contract termination payload')
        validate_optional_string!(body, 'reason', 'Termination reason', max_length: 500)
        validate_optional_string!(body, 'updated_at', 'updated_at')

        call('Failed to terminate contract') do
          http_post("#{contract_path(document_id, account_id_override)}/terminate", body)
        end
      end

      private

      def contract_path(document_id, account_id_override)
        doc_id = require_id(document_id, 'Document ID')
        "accounts/#{account_id(account_id_override)}/documents/#{doc_id}/contract"
      end

      def contract_list_params(params)
        query = query_params(require_payload(params, 'Contract filters'))
        reject_unknown_fields!(query, LIST_FIELDS, 'contract filters')
        validate_status_filter!(query)
        %w[counterparty search external_system external_id].each do |field|
          validate_optional_string!(query, field, field)
        end
        %w[end_date_from end_date_to].each { |field| validate_optional_date!(query, field) }
        if query['end_date_from'] && query['end_date_to'] && query['end_date_from'] > query['end_date_to']
          raise ValidationError.new('end_date_from must not be after end_date_to')
        end

        if query.key?('ending_within_days')
          validate_integer!(query['ending_within_days'], 'ending_within_days', 0, 3650)
        end
        validate_integer!(query['page'], 'page', 1) if query.key?('page')
        validate_integer!(query['per-page'], 'per_page', 1, 100) if query.key?('per-page')
        validate_enum!(query, 'sort', SORTS)
        validate_enum!(query, 'expand', %w[document])
        query
      end

      def validate_status_filter!(query)
        return unless query.key?('status')

        statuses = query['status'].is_a?(Array) ? query['status'] : query['status'].to_s.split(',')
        unless !statuses.empty? && statuses.all? { |status| status.is_a?(String) && STATUSES.include?(status) }
          raise ValidationError.new("status must contain only: #{STATUSES.join(', ')}")
        end

        query['status'] = statuses.join(',')
      end

      def contract_payload(payload, allowed, name)
        raw  = require_payload(payload, name)
        body = body_params(raw)
        raw.each { |key, value| body[key.to_s] = nil if value.nil? }
        reject_unknown_fields!(body, allowed, name.downcase)
        body
      end

      def validate_contract_input!(body)
        validate_enum!(body, 'status', STATUSES)
        validate_enum!(body, 'relation_type', RELATION_TYPES)
        validate_contract_strings!(body)
        validate_contract_dates!(body)
        validate_contract_numbers!(body)
        validate_contract_collections!(body)
      end

      def validate_contract_strings!(body)
        validate_optional_string!(body, 'counterparty_name', 'counterparty_name', max_length: 255)
        validate_optional_string!(body, 'counterparty_taxpayer_id', 'counterparty_taxpayer_id')
        validate_optional_string!(body, 'owner_id', 'owner_id')
        validate_optional_timestamp!(body, 'updated_at')
        validate_parent_document_id!(body)
        validate_currency!(body)
      end

      def validate_contract_dates!(body)
        %w[start_date end_date].each { |field| validate_optional_date!(body, field, minimum_year: 1000) }
        if body['start_date'] && body['end_date'] && body['start_date'] > body['end_date']
          raise ValidationError.new('end_date must not be before start_date')
        end
      end

      def validate_contract_numbers!(body)
        if body.key?('value') && !body['value'].nil?
          validate_number!(body['value'], 'value', 0, 9_999_999_999_999.99)
        end
        validate_boolean!(body, 'auto_renew')
        validate_integer!(body['renewal_term_months'], 'renewal_term_months', 1, 600) if body['renewal_term_months']
        validate_integer!(body['notice_period_days'], 'notice_period_days', 0, 3650) if body['notice_period_days']
      end

      def validate_contract_collections!(body)
        validate_metadata!(body['metadata']) if body.key?('metadata') && !body['metadata'].nil?
        if body.key?('external_references') && !body['external_references'].nil?
          validate_external_references!(body['external_references'])
        end
      end

      def validate_renewal!(body)
        unless body['term'] || body['end_date']
          raise ValidationError.new('Contract renewal requires term or end_date')
        end

        validate_optional_date!(body, 'end_date')
        validate_integer!(body['term'], 'term', 1) if body.key?('term')
        validate_number!(body['value'], 'value', 0, 9_999_999_999_999.99) if body.key?('value') && !body['value'].nil?
        validate_optional_timestamp!(body, 'updated_at')
      end

      def validate_parent_document_id!(body)
        return unless body.key?('parent_document_id') && !body['parent_document_id'].nil?

        require_id(body['parent_document_id'], 'parent_document_id')
      end

      def validate_currency!(body)
        return unless body.key?('currency') && !body['currency'].nil?

        currency = require_string(body['currency'], 'currency')
        raise ValidationError.new('currency must be a three-letter code') unless currency.match?(/\A[A-Za-z]{3}\z/)
      end

      def validate_optional_date!(body, field, minimum_year: nil)
        return unless body.key?(field) && !body[field].nil?

        value = require_string(body[field], field)
        date = Date.iso8601(value)
        raise ArgumentError unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/) && (!minimum_year || date.year >= minimum_year)
      rescue ArgumentError
        raise ValidationError.new("#{field} must be YYYY-MM-DD")
      end

      def validate_optional_string!(body, field, name, max_length: nil)
        return unless body.key?(field) && !body[field].nil?

        require_string(body[field], name, max_length: max_length)
      end

      def validate_enum!(body, field, allowed)
        return unless body.key?(field)

        value = require_string(body[field], field)
        return if allowed.include?(value)

        raise ValidationError.new("#{field} must be one of: #{allowed.join(', ')}")
      end

      def validate_boolean!(body, field)
        require_boolean(body[field], field) if body.key?(field) && !body[field].nil?
      end

      def validate_optional_timestamp!(body, field)
        return unless body.key?(field) && !body[field].nil?

        value = require_string(body[field], field)
        DateTime.iso8601(value)
        return if value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/)

        raise ArgumentError
      rescue ArgumentError
        raise ValidationError.new("#{field} must be an ISO 8601 timestamp with a timezone")
      end

      def validate_integer!(value, name, minimum, maximum = nil)
        valid = value.is_a?(Integer) && value >= minimum && (maximum.nil? || value <= maximum)
        return if valid

        range = maximum ? "between #{minimum} and #{maximum}" : "at least #{minimum}"
        raise ValidationError.new("#{name} must be an Integer #{range}")
      end

      def validate_number!(value, name, minimum, maximum = nil)
        number = value.is_a?(Integer) || value.is_a?(Float)
        finite = number && (!value.respond_to?(:finite?) || value.finite?)
        valid = finite && value.round(2) == value && value >= minimum && (maximum.nil? || value <= maximum)
        return if valid

        raise ValidationError.new("#{name} must be a finite number in the documented range")
      end

      def validate_metadata!(metadata)
        unless metadata.is_a?(Hash) && metadata.length <= 50
          raise ValidationError.new('metadata must be a Hash with at most 50 entries')
        end

        metadata.each do |key, value|
          valid_key = key.to_s.match?(/\A[A-Za-z0-9_.-]{1,40}\z/)
          valid_value = value.is_a?(String) && value.length <= 500
          next if valid_key && valid_value

          raise ValidationError.new('metadata keys or values are invalid')
        end
      end

      def validate_external_references!(references)
        unless references.is_a?(Array) && references.length <= 20
          raise ValidationError.new('external_references must be an Array with at most 20 entries')
        end

        references.each do |reference|
          unless reference.is_a?(Hash)
            raise ValidationError.new('Each external reference must be a Hash')
          end

          ref = reference.transform_keys(&:to_s)
          system = require_string(ref['system'], 'External reference system', max_length: 64)
          require_string(ref['id'], 'External reference ID', max_length: 255)
          unless system.match?(/\A[A-Za-z0-9_.-]+\z/)
            raise ValidationError.new('External reference system contains invalid characters')
          end
        end
      end

      def reject_unknown_fields!(body, allowed, name)
        unknown = body.keys - allowed
        raise ValidationError.new("Unknown #{name}: #{unknown.join(', ')}") unless unknown.empty?
      end
    end
  end
end
