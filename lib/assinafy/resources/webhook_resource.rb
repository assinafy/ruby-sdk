# frozen_string_literal: true

module Assinafy
  module Resources
    class WebhookResource < BaseResource
      def register(payload, account_id_override = nil)
        p = require_payload(payload, 'Webhook payload').transform_keys(&:to_sym)

        raise ValidationError.new('Webhook URL is required')   if p[:url].to_s.empty?
        raise ValidationError.new('Webhook email is required') if p[:email].to_s.empty?
        raise ValidationError.new('Webhook events are required') unless p[:events].is_a?(Array) && !p[:events].empty?

        acc_id = account_id(account_id_override)

        body = {
          url:       p[:url],
          email:     p[:email],
          events:    p[:events],
          is_active: p.key?(:is_active) ? p[:is_active] : true
        }

        @logger.info("Registering webhook #{p[:url]}")

        call('Failed to register webhook') do
          http_put("accounts/#{acc_id}/webhooks/subscriptions", body_params(body))
        end
      end

      alias update register

      def get(account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_optional('Failed to fetch webhook subscription') do
          http_get("accounts/#{acc_id}/webhooks/subscriptions")
        end
      end

      def delete(account_id_override = nil)
        acc_id = account_id(account_id_override)

        @logger.info('Deleting webhook subscription')

        call_void('Failed to delete webhook subscription') do
          http_delete("accounts/#{acc_id}/webhooks/subscriptions")
        end
      end

      def inactivate(account_id_override = nil)
        acc_id = account_id(account_id_override)

        @logger.info('Inactivating webhook subscription')

        call('Failed to inactivate webhook subscription') do
          http_put("accounts/#{acc_id}/webhooks/inactivate")
        end
      end

      def list_event_types
        call('Failed to list webhook event types') do
          http_get('webhooks/event-types')
        end
      end

      def list_dispatches(params = {}, account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_list('Failed to list webhook dispatches') do
          http_get("accounts/#{acc_id}/webhooks", params)
        end
      end

      def retry_dispatch(dispatch_id, account_id_override = nil)
        acc_id = account_id(account_id_override)
        did    = require_id(dispatch_id, 'Dispatch ID')

        call('Failed to retry webhook dispatch') do
          http_post("accounts/#{acc_id}/webhooks/#{did}/retry")
        end
      end
    end
  end
end
