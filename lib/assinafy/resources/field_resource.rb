# frozen_string_literal: true

module Assinafy
  module Resources
    class FieldResource < BaseResource
      def create(payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        body   = body_params(require_payload(payload))

        call('Failed to create field definition') do
          http_post("accounts/#{acc_id}/fields", body)
        end
      end

      def list(params = {}, account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_list('Failed to list field definitions') do
          http_get("accounts/#{acc_id}/fields", params)
        end
      end

      def get(field_id, account_id_override = nil)
        acc_id = account_id(account_id_override)
        fid    = require_id(field_id, 'Field ID')

        call('Failed to fetch field definition') do
          http_get("accounts/#{acc_id}/fields/#{fid}")
        end
      end

      def update(field_id, payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        fid    = require_id(field_id, 'Field ID')
        body   = body_params(require_payload(payload))

        call('Failed to update field definition') do
          http_put("accounts/#{acc_id}/fields/#{fid}", body)
        end
      end

      def delete(field_id, account_id_override = nil)
        acc_id = account_id(account_id_override)
        fid    = require_id(field_id, 'Field ID')

        call_void('Failed to delete field definition') do
          http_delete("accounts/#{acc_id}/fields/#{fid}")
        end
      end

      def validate(field_id, value, account_id_override = nil, signer_access_code: nil)
        acc_id = account_id(account_id_override)
        fid    = require_id(field_id, 'Field ID')

        call('Failed to validate field value') do
          http_post("accounts/#{acc_id}/fields/#{fid}/validate", body_params(value: value),
                    signer_access_code: signer_access_code)
        end
      end

      def validate_multiple(values, account_id_override = nil, signer_access_code: nil)
        acc_id = account_id(account_id_override)
        list   = require_array(values, 'Field values')

        call('Failed to validate field values') do
          http_post("accounts/#{acc_id}/fields/validate-multiple",
                    list.map { |item| item.is_a?(Hash) ? body_params(item) : item },
                    signer_access_code: signer_access_code)
        end
      end

      def types
        call('Failed to list field types') do
          http_get('field-types')
        end
      end
    end
  end
end
