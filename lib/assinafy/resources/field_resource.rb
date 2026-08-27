# frozen_string_literal: true

module Assinafy
  module Resources
    # Field definitions (reusable input fields) and per-value validation.
    #
    # See https://api.assinafy.com.br/v1/docs#field-definition for the
    # documentation of these endpoints.
    class FieldResource < BaseResource
      # Create a field definition.
      #
      # @param payload [Hash]
      # @option payload [String]  :type        required — e.g. `text`, `cpf`, `email` — see {#types}
      # @option payload [String]  :name        required — display label
      # @option payload [String]  :regex       optional validation regex (text fields)
      # @option payload [Boolean] :is_required default `true`
      # @param account_id_override [String, nil]
      # @return [Hash] the created field definition (envelope `data` unwrapped)
      # @see POST /accounts/{accountId}/fields
      # @example Create a text field
      #   field = client.fields.create(type: 'text', name: 'customer-reference')
      #
      #   # Request body the SDK sends:
      #   #   { "type": "text", "name": "customer-reference" }
      #
      #   # => {
      #   #   "resource"       => "field_definition",
      #   #   "id"             => "1032009e858cc1f859ccf3a61229",
      #   #   "name"           => "customer-reference",
      #   #   "type"           => "text",
      #   #   "regex"          => nil,
      #   #   "is_pre_defined" => false,
      #   #   "is_active"      => true,
      #   #   "is_required"    => true,
      #   #   "is_standard"    => false,
      #   #   "is_read_only"   => false,
      #   #   "is_visible"     => true
      #   # }
      def create(payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        body   = body_params(require_payload(payload))

        call('Failed to create field definition') do
          http_post("accounts/#{acc_id}/fields", body)
        end
      end

      # List field definitions.
      #
      # NOTE: this endpoint does not send pagination headers, so `meta` is always
      # `nil` here (unlike other list endpoints which return a pagination Hash).
      #
      # @param params [Hash] `include_inactive`, `include_standard`
      # @param account_id_override [String, nil]
      # @return [Hash{Symbol=>Array,nil}] `{ data: [...], meta: nil }`
      # @see GET /accounts/{accountId}/fields
      # @example List including inactive fields
      #   result = client.fields.list(include_inactive: true)
      #
      #   # => {
      #   #   data: [
      #   #     {
      #   #       "id"             => "field-id",
      #   #       "name"           => "Nome",
      #   #       "type"           => "personName",
      #   #       "regex"          => nil,
      #   #       "is_pre_defined" => true,
      #   #       "is_active"      => true,
      #   #       "is_required"    => false,
      #   #       "is_standard"    => false,
      #   #       "is_read_only"   => false,
      #   #       "is_visible"     => true
      #   #     }
      #   #     # ... (one Hash per field definition)
      #   #   ],
      #   #   meta: nil # this endpoint sends no pagination headers
      #   # }
      def list(params = {}, account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_list('Failed to list field definitions') do
          http_get("accounts/#{acc_id}/fields", params)
        end
      end

      # Fetch a field definition by ID.
      #
      # @param field_id            [String]
      # @param account_id_override [String, nil]
      # @return [Hash] the field definition (envelope `data` unwrapped)
      # @see GET /accounts/{accountId}/fields/{field_id}
      # @example Fetch one field definition
      #   field = client.fields.get('1032009e858cc1f859ccf3a61229')
      #
      #   # => {
      #   #   "resource"       => "field_definition",
      #   #   "id"             => "1032009e858cc1f859ccf3a61229",
      #   #   "name"           => "customer-reference",
      #   #   "type"           => "text",
      #   #   "regex"          => nil,
      #   #   "is_pre_defined" => false,
      #   #   "is_active"      => true,
      #   #   "is_required"    => true,
      #   #   "is_standard"    => false,
      #   #   "is_read_only"   => false,
      #   #   "is_visible"     => true
      #   # }
      def get(field_id, account_id_override = nil)
        acc_id = account_id(account_id_override)
        fid    = require_id(field_id, 'Field ID')

        call('Failed to fetch field definition') do
          http_get("accounts/#{acc_id}/fields/#{fid}")
        end
      end

      # Update a field definition. The update endpoint accepts only `name`,
      # `regex`, and `is_active` (unlike {#create}, it does not accept `type`
      # or `is_required`).
      #
      # @param field_id            [String]
      # @param payload             [Hash]
      # @option payload [String]  :name      display label
      # @option payload [String]  :regex     validation regex (text fields)
      # @option payload [Boolean] :is_active enable/disable the field
      # @param account_id_override [String, nil]
      # @return [Hash] the updated field definition (envelope `data` unwrapped)
      # @see PUT /accounts/{account_id}/fields/{field_id}
      # @example Rename a field definition
      #   field = client.fields.update('1032009e858cc1f859ccf3a61229', name: 'New Field Name')
      #
      #   # Request body the SDK sends:
      #   #   { "name": "New Field Name" }
      #
      #   # => {
      #   #   "resource"       => "field_definition",
      #   #   "id"             => "1032009e858cc1f859ccf3a61229",
      #   #   "name"           => "New Field Name",
      #   #   "type"           => "text",
      #   #   "regex"          => nil,
      #   #   "is_pre_defined" => false,
      #   #   "is_active"      => true,
      #   #   "is_required"    => true,
      #   #   "is_standard"    => false,
      #   #   "is_read_only"   => false,
      #   #   "is_visible"     => true
      #   # }
      def update(field_id, payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        fid    = require_id(field_id, 'Field ID')
        raw    = require_payload(payload)
        body   = body_params(raw)
        body['regex'] = nil if (raw.key?(:regex) && raw[:regex].nil?) ||
                               (raw.key?('regex') && raw['regex'].nil?)

        call('Failed to update field definition') do
          http_put("accounts/#{acc_id}/fields/#{fid}", body)
        end
      end

      # Delete a field definition. Fields used by any document cannot be deleted.
      #
      # @param field_id            [String]
      # @param account_id_override [String, nil]
      # @return [nil] the API returns `data: []`; the SDK normalizes this to `nil`
      # @see DELETE /accounts/{account_id}/fields/{field_id}
      # @example Delete a field definition
      #   client.fields.delete('1032009e858cc1f859ccf3a61229')
      #   # => nil
      def delete(field_id, account_id_override = nil)
        acc_id = account_id(account_id_override)
        fid    = require_id(field_id, 'Field ID')

        call_void('Failed to delete field definition') do
          http_delete("accounts/#{acc_id}/fields/#{fid}")
        end
      end

      # Validate a single value against a field definition.
      #
      # The OpenAPI declares workspace Authorization. The deployed API also
      # accepts signer-access-code authentication; pass `signer_access_code:`
      # to use that compatibility path without sending workspace credentials.
      #
      # @param field_id             [String]
      # @param value                [Object]
      # @param account_id_override  [String, nil]
      # @param signer_access_code   [String, nil]
      # @return [Hash{String=>Object}] `{ "type" =>, "success" =>, "error_message" => }`
      # @see POST /accounts/{accountId}/fields/{field_id}/validate
      # @example Validate a value (workspace auth)
      #   result = client.fields.validate('1032009e858cc1f859ccf3a61229', 'Some text')
      #
      #   # Request body the SDK sends:
      #   #   { "value": "Some text" }
      #
      #   # => { "type" => "text", "success" => true, "error_message" => "" }
      #
      # @example Validate as a signer (signer-access-code auth, sent as a query param)
      #   client.fields.validate('field-id', 'Some text', signer_access_code: 'signer-access-code')
      #   # => { "type" => "text", "success" => true, "error_message" => "" }
      def validate(field_id, value, account_id_override = nil, signer_access_code: nil)
        acc_id      = account_id(account_id_override)
        fid         = require_id(field_id, 'Field ID')
        raise ValidationError.new('Field value is required') if value.nil?

        access_code = signer_access_code.nil? ? nil : require_signer_access_code(signer_access_code)

        call('Failed to validate field value') do
          http_post("accounts/#{acc_id}/fields/#{fid}/validate", body_params(value: value),
                    { signer_access_code: access_code }, workspace_auth: access_code.nil?)
        end
      end

      # Validate many `{ field_id:, value: }` pairs in a single call.
      #
      # As with {#validate}, signer-access-code support is a deployed-API
      # compatibility extension beyond the current OpenAPI security declaration.
      #
      # @param values               [Array<Hash>]
      # @param account_id_override  [String, nil]
      # @param signer_access_code   [String, nil]
      # @return [Array<Hash>] one validation Hash per input, each carrying its `field_id`
      # @see POST /accounts/{accountId}/fields/validate-multiple
      # @example Validate several values at once
      #   results = client.fields.validate_multiple([
      #     { field_id: '63488ffb7adf435aba319787', value: '1111111111111' },
      #     { field_id: '63488ffb0461cebb70775497', value: 'user@example.com' }
      #   ])
      #
      #   # Request body the SDK sends (an array, not an object):
      #   #   [
      #   #     { "field_id": "63488ffb7adf435aba319787", "value": "1111111111111" },
      #   #     { "field_id": "63488ffb0461cebb70775497", "value": "user@example.com" }
      #   #   ]
      #
      #   # => [
      #   #   { "field_id" => "63488ffb7adf435aba319787", "type" => "cpf",
      #   #     "success" => false, "error_message" => "Invalid CPF." },
      #   #   { "field_id" => "63488ffb0461cebb70775497", "type" => "email",
      #   #     "success" => true, "error_message" => "" }
      #   # ]
      def validate_multiple(values, account_id_override = nil, signer_access_code: nil)
        acc_id      = account_id(account_id_override)
        list        = require_array(values, 'Field values')
        access_code = signer_access_code.nil? ? nil : require_signer_access_code(signer_access_code)

        call_array('Failed to validate field values') do
          http_post("accounts/#{acc_id}/fields/validate-multiple",
                    list.map { |item| field_value_payload(item) },
                    { signer_access_code: access_code }, workspace_auth: access_code.nil?)
        end
      end

      # List the catalog of supported field types.
      #
      # @return [Array<Hash{String=>String}>] each entry is `{ "type" =>, "name" => }`
      # @see GET /field-types
      # @example List supported field types
      #   types = client.fields.types
      #
      #   # => [
      #   #   { "type" => "personName",  "name" => "Nome" },
      #   #   { "type" => "cpf",         "name" => "CPF" },
      #   #   { "type" => "phoneNumber", "name" => "Número de Telefone" },
      #   #   { "type" => "postalCode",  "name" => "CEP" },
      #   #   { "type" => "email",       "name" => "E-mail" },
      #   #   { "type" => "cnpj",        "name" => "CNPJ" },
      #   #   { "type" => "companyName", "name" => "Nome da empresa" },
      #   #   { "type" => "email",       "name" => "E-mail" }, # the live catalog lists "email" twice
      #   #   { "type" => "text",        "name" => "Texto" },
      #   #   { "type" => "number",      "name" => "Número" },
      #   #   { "type" => "date",        "name" => "Data" }
      #   # ]
      def types
        call_array('Failed to list field types') do
          http_get('field-types')
        end
      end

      private

      def field_value_payload(item)
        payload = require_payload(item, 'Field value')
        field_id = payload.key?(:field_id) ? payload[:field_id] : payload['field_id']
        value_key = payload.key?(:value) ? :value : 'value'

        require_id(field_id, 'Field ID')
        unless payload.key?(value_key) && !payload[value_key].nil?
          raise ValidationError.new('Field value is required')
        end

        body_params(payload)
      end
    end
  end
end
