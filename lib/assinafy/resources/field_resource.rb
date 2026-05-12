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
      # @option payload [String]  :type        e.g. `text`, `cpf`, `email` — see {#types}
      # @option payload [String]  :name        display label
      # @option payload [String]  :regex       optional validation regex (text fields)
      # @option payload [Boolean] :is_required default `true`
      # @option payload [Boolean] :is_active   default `true`
      # @param account_id_override [String, nil]
      # @return [Hash]
      # @see POST /accounts/{accountId}/fields
      def create(payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        body   = body_params(require_payload(payload))

        call('Failed to create field definition') do
          http_post("accounts/#{acc_id}/fields", body)
        end
      end

      # List field definitions with pagination metadata.
      #
      # @param params [Hash] `include_inactive`, `include_standard`, `page`, `per_page`
      # @param account_id_override [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [...], meta: { ... } }`
      # @see GET /accounts/{accountId}/fields
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
      # @return [Hash]
      # @see GET /accounts/{accountId}/fields/{field_id}
      def get(field_id, account_id_override = nil)
        acc_id = account_id(account_id_override)
        fid    = require_id(field_id, 'Field ID')

        call('Failed to fetch field definition') do
          http_get("accounts/#{acc_id}/fields/#{fid}")
        end
      end

      # Update a field definition.
      #
      # @param field_id            [String]
      # @param payload             [Hash] same fields as {#create}
      # @param account_id_override [String, nil]
      # @return [Hash]
      # @see PUT /accounts/{account_id}/fields/{field_id}
      def update(field_id, payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        fid    = require_id(field_id, 'Field ID')
        body   = body_params(require_payload(payload))

        call('Failed to update field definition') do
          http_put("accounts/#{acc_id}/fields/#{fid}", body)
        end
      end

      # Delete a field definition. Fields used by any document cannot be deleted.
      #
      # @param field_id            [String]
      # @param account_id_override [String, nil]
      # @return [nil]
      # @see DELETE /accounts/{account_id}/fields/{field_id}
      def delete(field_id, account_id_override = nil)
        acc_id = account_id(account_id_override)
        fid    = require_id(field_id, 'Field ID')

        call_void('Failed to delete field definition') do
          http_delete("accounts/#{acc_id}/fields/#{fid}")
        end
      end

      # Validate a single value against a field definition.
      #
      # Either workspace Authorization or signer-access-code authentication
      # works; pass `signer_access_code:` for the latter.
      #
      # @param field_id             [String]
      # @param value                [Object]
      # @param account_id_override  [String, nil]
      # @param signer_access_code   [String, nil]
      # @return [Hash]
      # @see POST /accounts/{accountId}/fields/{field_id}/validate
      def validate(field_id, value, account_id_override = nil, signer_access_code: nil)
        acc_id = account_id(account_id_override)
        fid    = require_id(field_id, 'Field ID')

        call('Failed to validate field value') do
          http_post("accounts/#{acc_id}/fields/#{fid}/validate", body_params(value: value),
                    signer_access_code: signer_access_code)
        end
      end

      # Validate many `{ field_id:, value: }` pairs in a single call.
      #
      # @param values               [Array<Hash>]
      # @param account_id_override  [String, nil]
      # @param signer_access_code   [String, nil]
      # @return [Array<Hash>]
      # @see POST /accounts/{accountId}/fields/validate-multiple
      def validate_multiple(values, account_id_override = nil, signer_access_code: nil)
        acc_id = account_id(account_id_override)
        list   = require_array(values, 'Field values')

        call('Failed to validate field values') do
          http_post("accounts/#{acc_id}/fields/validate-multiple",
                    list.map { |item| item.is_a?(Hash) ? body_params(item) : item },
                    signer_access_code: signer_access_code)
        end
      end

      # List the catalog of supported field types.
      #
      # @return [Array<Hash>]
      # @see GET /field-types
      def types
        call('Failed to list field types') do
          http_get('field-types')
        end
      end
    end
  end
end
