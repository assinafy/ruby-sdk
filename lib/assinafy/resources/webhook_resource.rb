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
      # @return [Hash] the subscription object: { events:, is_active:, url:, email:, updated_at: }
      # @see PUT /accounts/{account_id}/webhooks/subscriptions
      # @example Register (or replace) the subscription
      #   client.webhooks.register(
      #     url:    'https://example.com/webhook',
      #     email:  'ops@example.com',
      #     events: %w[document_ready document_prepared]
      #   )
      #   # PUT /accounts/{account_id}/webhooks/subscriptions
      #   # request body sent by the SDK:
      #   # {
      #   #   "url":       "https://example.com/webhook",
      #   #   "email":     "ops@example.com",
      #   #   "events":    ["document_ready", "document_prepared"],
      #   #   "is_active": true
      #   # }
      #   # => unwrapped data payload returned:
      #   # {
      #   #   events:     ["document_ready", "document_prepared"],
      #   #   is_active:  true,
      #   #   url:        "https://example.com/webhook",
      #   #   email:      "ops@example.com",
      #   #   updated_at: "2026-06-05T21:13:24Z"
      #   # }
      def register(payload, account_id_override = nil)
        p = require_payload(payload, 'Webhook payload').transform_keys(&:to_sym)

        raise ValidationError.new('Webhook URL is required')   if p[:url].to_s.strip.empty?
        raise ValidationError.new('Webhook email is required') if p[:email].to_s.strip.empty?

        events = require_array(p[:events], 'Webhook events')
        unless events.all? { |event| event.is_a?(String) && !event.strip.empty? }
          raise ValidationError.new('Webhook events must be non-empty Strings')
        end

        acc_id = account_id(account_id_override)

        body = {
          url:       p[:url],
          email:     p[:email],
          events:    events,
          is_active: p.key?(:is_active) ? require_boolean(p[:is_active], 'is_active') : true
        }

        @logger.info('Registering webhook subscription')

        call('Failed to register webhook') do
          http_put("accounts/#{acc_id}/webhooks/subscriptions", body_params(body))
        end
      end

      alias update register

      # Fetch the current webhook subscription. Returns `nil` on 404
      # (no subscription configured yet).
      #
      # @param account_id_override [String, nil]
      # @return [Hash, nil] subscription object, or `nil` when none is configured (404)
      # @see GET /accounts/{account_id}/webhooks/subscriptions
      # @example Fetch the current subscription
      #   client.webhooks.get
      #   # GET /accounts/{account_id}/webhooks/subscriptions
      #   # => unwrapped data payload returned (nil if no subscription exists):
      #   # {
      #   #   events:     ["document_ready", "signer_signed_document"],
      #   #   is_active:  false,
      #   #   url:        "https://example.com/sdk-smoke-webhook",
      #   #   email:      "webhook@example.com",
      #   #   updated_at: "2026-06-05T21:13:24Z"
      #   # }
      def get(account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_optional('Failed to fetch webhook subscription') do
          http_get("accounts/#{acc_id}/webhooks/subscriptions")
        end
      end

      # Inactivate (but keep) the account's webhook subscription. Stops
      # deliveries without losing the configured event set.
      #
      # @param account_id_override [String, nil]
      # @return [Hash] the subscription object with `is_active: false`; the event set is preserved
      # @see PUT /accounts/{account_id}/webhooks/inactivate
      # @example Inactivate without losing the configured events
      #   client.webhooks.inactivate
      #   # PUT /accounts/{account_id}/webhooks/inactivate  (no request body)
      #   # => unwrapped data payload returned:
      #   # {
      #   #   events:     ["document_ready", "document_prepared"],
      #   #   is_active:  false,
      #   #   url:        "https://example.com/webhook",
      #   #   email:      "ops@example.com",
      #   #   updated_at: "2026-06-05T21:13:24Z"
      #   # }
      def inactivate(account_id_override = nil)
        acc_id = account_id(account_id_override)

        @logger.info('Inactivating webhook subscription')

        call('Failed to inactivate webhook subscription') do
          http_put("accounts/#{acc_id}/webhooks/inactivate")
        end
      end

      # Catalogue of supported event-type identifiers.
      #
      # @return [Array<Hash>] each entry is { id:, description: } (18 event types available)
      # @see GET /webhooks/event-types
      # @example List subscribable event types
      #   client.webhooks.list_event_types
      #   # GET /webhooks/event-types
      #   # => unwrapped data payload returned (18 entries):
      #   # [
      #   #   { id: "document_uploaded",        description: "Triggered when the User has uploaded a Document" },
      #   #   { id: "document_metadata_ready",  description: "Triggered when the document is ready to be prepared..." },
      #   #   { id: "document_prepared",        description: "Triggered when the User prepares a Document." },
      #   #   { id: "assignment_created",       description: "Triggered when the User created an assignment..." },
      #   #   { id: "signature_requested",      description: "Triggered when the User requested signature..." },
      #   #   { id: "document_ready",           description: "Triggered when the last Signer signs the Document..." },
      #   #   { id: "signer_created",           description: "Triggered when the User created a Signer" },
      #   #   { id: "signer_email_verified",    description: "Triggered when Signer's email has been verified..." }
      #   #   # ... (see docs for the full 18-event catalogue)
      #   # ]
      def list_event_types
        call_array('Failed to list webhook event types') do
          http_get('webhooks/event-types')
        end
      end

      # List webhook delivery attempts (dispatches) with pagination metadata.
      #
      # @param params [Hash] `event`, `delivered`, `from`, `to`, `page`, `per-page`
      # @param account_id_override [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [dispatch, ...], meta: { current_page:, per_page:, total:,
      #   last_page: } }`
      # @see GET /accounts/{account_id}/webhooks
      # @example List delivery attempts, filtered to undelivered
      #   client.webhooks.list_dispatches(delivered: false, 'per-page': 20)
      #   # GET /accounts/{account_id}/webhooks?delivered=false&per-page=20
      #   # => unwrapped data payload returned (pagination from x-pagination-* headers):
      #   # {
      #   #   data: [
      #   #     {
      #   #       id:            "dispatch-id",
      #   #       event:         "signature_requested",
      #   #       activity_id:   15431,
      #   #       endpoint:      "https://example.com/webhook",
      #   #       payload:       { id: 15431, event: "signature_requested", object: {}, subject: {}, payload: {} },
      #   #       delivered:     false,
      #   #       http_status:   404,
      #   #       response_body: "{\"success\":false,...}",
      #   #       error:         "Client error: `POST https://example.com/webhook` resulted in a 404 ...",
      #   #       created_at:    "2026-07-20T15:57:38Z",
      #   #       updated_at:    "2026-07-20T15:57:38Z"
      #   #     }
      #   #     # ... (see docs for full dispatch shape)
      #   #   ],
      #   #   meta: { current_page: 1, per_page: 20, total: 2, last_page: 1 }
      #   # }
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
      # @return [Hash] the freshly created dispatch entry (same shape as {#list_dispatches}, plus `resource`)
      # @see POST /accounts/{account_id}/webhooks/{dispatch_id}/retry
      # @example Force a single dispatch to be re-attempted
      #   client.webhooks.retry_dispatch('dispatch-id')
      #   # POST /accounts/{account_id}/webhooks/dispatch-id/retry  (no request body)
      #   # => unwrapped data payload returned:
      #   # {
      #   #   resource:      "activity_dispatching_history",
      #   #   id:            "dispatch-id",
      #   #   event:         "signature_requested",
      #   #   activity_id:   15431,
      #   #   endpoint:      "https://example.com/webhook",
      #   #   payload:       { id: 15431, event: "signature_requested", object: {}, subject: {} },
      #   #   delivered:     true,
      #   #   http_status:   200,
      #   #   response_body: "OK",
      #   #   error:         nil,
      #   #   created_at:    "2026-07-20T15:57:38Z",
      #   #   updated_at:    "2026-07-20T15:57:39Z"
      #   # }
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
