# frozen_string_literal: true

module Assinafy
  module Resources
    # Webhook subscription, event-type catalog, delivery history, and retries.
    #
    # See https://api.assinafy.com.br/v1/docs#webhooks for the full
    # documentation of these endpoints.
    class WebhookResource < BaseResource
      # Create or replace the account's webhook subscription. The API uses
      # `PUT subscriptions` for both create and update semantics, hence the
      # name `register` (with an `update` alias).
      #
      # @param payload [Hash]
      # @option payload [String]        :url       endpoint that will receive events
      # @option payload [String]        :email     contact email for delivery health
      # @option payload [Array<String>] :events    event-type IDs (see {#list_event_types})
      # @option payload [Boolean]       :is_active default `true` when omitted
      # @param account_id_override [String, nil]
      # @return [Hash]
      # @see PUT /accounts/{account_id}/webhooks/subscriptions
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

      # Fetch the current webhook subscription. Returns `nil` on 404
      # (no subscription configured yet).
      #
      # @param account_id_override [String, nil]
      # @return [Hash, nil]
      # @see GET /accounts/{account_id}/webhooks/subscriptions
      def get(account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_optional('Failed to fetch webhook subscription') do
          http_get("accounts/#{acc_id}/webhooks/subscriptions")
        end
      end

      # Delete the account's webhook subscription.
      #
      # @param account_id_override [String, nil]
      # @return [nil]
      # @see DELETE /accounts/{account_id}/webhooks/subscriptions
      def delete(account_id_override = nil)
        acc_id = account_id(account_id_override)

        @logger.info('Deleting webhook subscription')

        call_void('Failed to delete webhook subscription') do
          http_delete("accounts/#{acc_id}/webhooks/subscriptions")
        end
      end

      # Inactivate (but keep) the account's webhook subscription. Stops
      # deliveries without losing the configured event set.
      #
      # @param account_id_override [String, nil]
      # @return [Hash]
      # @see PUT /accounts/{account_id}/webhooks/inactivate
      def inactivate(account_id_override = nil)
        acc_id = account_id(account_id_override)

        @logger.info('Inactivating webhook subscription')

        call('Failed to inactivate webhook subscription') do
          http_put("accounts/#{acc_id}/webhooks/inactivate")
        end
      end

      # Catalogue of supported event-type identifiers.
      #
      # @return [Array<Hash>]
      # @see GET /webhooks/event-types
      def list_event_types
        call('Failed to list webhook event types') do
          http_get('webhooks/event-types')
        end
      end

      # List webhook delivery attempts (dispatches) with pagination metadata.
      #
      # @param params [Hash] `event`, `delivered`, `from`, `to`, `page`, `per_page`
      # @param account_id_override [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [...], meta: { ... } }`
      # @see GET /accounts/{account_id}/webhooks
      def list_dispatches(params = {}, account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_list('Failed to list webhook dispatches') do
          http_get("accounts/#{acc_id}/webhooks", params)
        end
      end

      # Force a single dispatch to be re-attempted.
      #
      # @param dispatch_id [String]
      # @param account_id_override [String, nil]
      # @return [Hash] the freshly created dispatch entry
      # @see POST /accounts/{account_id}/webhooks/{dispatch_id}/retry
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
