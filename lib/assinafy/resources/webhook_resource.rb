# frozen_string_literal: true

module Assinafy
  module Resources
    # Webhook endpoints, signing secrets, the legacy single subscription,
    # event-type catalog, delivery history, and retries.
    #
    # An account can register 1 endpoint, or up to 3 on paid plans. Every active
    # endpoint subscribed to an event receives it. The `subscriptions` methods
    # ({#register}, {#get}, {#inactivate}) act on the account's oldest endpoint.
    #
    # See https://api.assinafy.com.br/v1/docs#webhooks for the full
    # documentation of these endpoints.
    class WebhookResource < BaseResource
      ENDPOINT_FIELDS     = %i[url email events name is_active signing_enabled].freeze
      SUBSCRIPTION_FIELDS = %i[url email events is_active].freeze
      REQUIRED_FIELDS     = %i[url email events].freeze

      # Create or replace the account's oldest webhook endpoint (creating it
      # when the account has none). The API uses `PUT subscriptions` for both
      # create and update semantics, hence the name `register` (with an
      # `update` alias). Accounts with several endpoints should use
      # {#create_endpoint} / {#update_endpoint}.
      #
      # @param payload [Hash]
      # @option payload [String]        :url       endpoint that will receive events
      # @option payload [String]        :email     contact email for delivery health
      # @option payload [Array<String>] :events    event-type IDs (see {#list_event_types})
      # @option payload [Boolean]       :is_active default `true` when omitted
      # @param account_id_override [String, nil]
      # @return [Hash] the subscription object: { events:, is_active:, url:, email:, updated_at: }
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
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
        body   = { is_active: true }.merge(webhook_body(payload, SUBSCRIPTION_FIELDS, REQUIRED_FIELDS))
        acc_id = account_id(account_id_override)

        @logger.info('Registering webhook subscription')

        call('Failed to register webhook') do
          http_put("accounts/#{acc_id}/webhooks/subscriptions", body_params(body))
        end
      end

      alias update register

      # Fetch the account's oldest webhook endpoint. Returns `nil` on 404
      # (no endpoint configured yet).
      #
      # @param account_id_override [String, nil]
      # @return [Hash, nil] subscription object, or `nil` when none is configured (404)
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
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

      # Inactivate (but keep) the account's oldest webhook endpoint. Stops
      # deliveries to it without losing the configured event set; other
      # endpoints are unaffected.
      #
      # @param account_id_override [String, nil]
      # @return [Hash] the subscription object with `is_active: false`; the event set is preserved
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
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
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
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
      # @param params [Hash] `endpoint_id`, `event`, `delivered`, `from`, `to`, `page`, `per_page`
      # @param account_id_override [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [dispatch, ...], meta: { current_page:, per_page:, total:,
      #   last_page: } }`
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
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
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
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

      # List the account's webhook endpoints, oldest first.
      #
      # @param account_id_override [String, nil]
      # @return [Array<Hash>] webhook endpoint objects
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see GET /accounts/{account_id}/webhooks/endpoints
      # @example List endpoints
      #   client.webhooks.list_endpoints
      #   # GET /accounts/{account_id}/webhooks/endpoints
      #   # => unwrapped data payload returned:
      #   # [
      #   #   {
      #   #     id:              "webhook-endpoint-id",
      #   #     name:            "ERP",
      #   #     url:             "https://example.com/webhooks/assinafy",
      #   #     email:           "ops@example.com",
      #   #     events:          ["document_ready", "signer_signed_document"],
      #   #     is_active:       true,
      #   #     signing_enabled: true,
      #   #     created_at:      "2026-10-01T12:00:00Z",
      #   #     updated_at:      "2026-10-01T12:00:00Z"
      #   #   }
      #   # ]
      def list_endpoints(account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_array('Failed to list webhook endpoints') do
          http_get("accounts/#{acc_id}/webhooks/endpoints")
        end
      end

      # Register a new webhook endpoint. Each endpoint of an account needs a
      # distinct `url`. Creating one past the plan's limit (1, or 3 on paid
      # plans) answers `403`. With `signing_enabled: true` a signing secret is
      # generated; read it with {#endpoint_secret}.
      #
      # @param payload [Hash]
      # @option payload [String]        :url             http(s) URL that receives the events (required)
      # @option payload [String]        :email           contact email for delivery-failure notices (required)
      # @option payload [Array<String>] :events          event-type IDs (see {#list_event_types}) (required)
      # @option payload [String]        :name            label to tell endpoints apart
      # @option payload [Boolean]       :is_active       API default `true`
      # @option payload [Boolean]       :signing_enabled API default `false`
      # @param account_id_override [String, nil]
      # @return [Hash] the created endpoint
      # @raise [Assinafy::ApiError] `400` on a duplicate URL or invalid body; `403` past the plan limit
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid or unknown input
      # @see POST /accounts/{account_id}/webhooks/endpoints
      # @example Create a signed endpoint
      #   client.webhooks.create_endpoint(
      #     url:             'https://example.com/webhooks/assinafy',
      #     email:           'ops@example.com',
      #     events:          %w[document_ready signer_signed_document],
      #     name:            'ERP',
      #     signing_enabled: true
      #   )
      #   # POST /accounts/{account_id}/webhooks/endpoints
      #   # request body sent by the SDK:
      #   # {
      #   #   "url":             "https://example.com/webhooks/assinafy",
      #   #   "email":           "ops@example.com",
      #   #   "events":          ["document_ready", "signer_signed_document"],
      #   #   "name":            "ERP",
      #   #   "signing_enabled": true
      #   # }
      #   # => unwrapped data payload returned (same shape as {#list_endpoints} entries):
      #   # { id: "webhook-endpoint-id", name: "ERP", url: "https://example.com/webhooks/assinafy",
      #   #   email: "ops@example.com", events: [...], is_active: true, signing_enabled: true,
      #   #   created_at: "2026-10-01T12:00:00Z", updated_at: "2026-10-01T12:00:00Z" }
      def create_endpoint(payload, account_id_override = nil)
        body   = webhook_body(payload, ENDPOINT_FIELDS, REQUIRED_FIELDS)
        acc_id = account_id(account_id_override)

        @logger.info('Creating webhook endpoint')

        call('Failed to create webhook endpoint') do
          http_post("accounts/#{acc_id}/webhooks/endpoints", body_params(body))
        end
      end

      # Fetch one webhook endpoint.
      #
      # @param endpoint_id [String]
      # @param account_id_override [String, nil]
      # @return [Hash] the endpoint (same shape as {#list_endpoints} entries)
      # @raise [Assinafy::ApiError] on an unsuccessful API response; `404` on an unknown ID
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see GET /accounts/{account_id}/webhooks/endpoints/{endpoint_id}
      # @example Fetch an endpoint
      #   client.webhooks.get_endpoint('webhook-endpoint-id')
      #   # GET /accounts/{account_id}/webhooks/endpoints/webhook-endpoint-id
      #   # => { id: "webhook-endpoint-id", name: "ERP", url: "https://example.com/webhooks/assinafy", ... }
      def get_endpoint(endpoint_id, account_id_override = nil)
        call('Failed to fetch webhook endpoint') do
          http_get(endpoint_path(endpoint_id, account_id_override))
        end
      end

      # Change a webhook endpoint. Only the fields sent are updated.
      # `signing_enabled: true` generates a secret when the endpoint has none
      # and keeps the current one otherwise; `false` discards the secret.
      #
      # @param endpoint_id [String]
      # @param payload [Hash] any of `url`, `email`, `events`, `name`, `is_active`, `signing_enabled`
      # @param account_id_override [String, nil]
      # @return [Hash] the updated endpoint
      # @raise [Assinafy::ApiError] `400` when `url` is used by another endpoint; `404` on an unknown ID
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on an empty, invalid, or unknown payload
      # @see PUT /accounts/{account_id}/webhooks/endpoints/{endpoint_id}
      # @example Pause an endpoint
      #   client.webhooks.update_endpoint('webhook-endpoint-id', is_active: false)
      #   # PUT /accounts/{account_id}/webhooks/endpoints/webhook-endpoint-id
      #   # request body sent by the SDK:
      #   # { "is_active": false }
      #   # => { id: "webhook-endpoint-id", is_active: false, ... }
      def update_endpoint(endpoint_id, payload, account_id_override = nil)
        body = webhook_body(payload, ENDPOINT_FIELDS, [])
        raise ValidationError.new('Webhook endpoint update must change at least one field') if body.empty?

        path = endpoint_path(endpoint_id, account_id_override)

        call('Failed to update webhook endpoint') do
          http_put(path, body_params(body))
        end
      end

      # Delete a webhook endpoint and free its slot.
      #
      # @param endpoint_id [String]
      # @param account_id_override [String, nil]
      # @return [nil]
      # @raise [Assinafy::ApiError] on an unsuccessful API response; `404` on an unknown ID
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see DELETE /accounts/{account_id}/webhooks/endpoints/{endpoint_id}
      # @example Delete an endpoint
      #   client.webhooks.delete_endpoint('webhook-endpoint-id')
      #   # DELETE /accounts/{account_id}/webhooks/endpoints/webhook-endpoint-id  (no request body)
      #   # => nil
      def delete_endpoint(endpoint_id, account_id_override = nil)
        path = endpoint_path(endpoint_id, account_id_override)

        @logger.info('Deleting webhook endpoint')

        call_void('Failed to delete webhook endpoint') do
          http_delete(path)
        end
      end

      # Read the Standard Webhooks secret that signs deliveries to an endpoint.
      # Pass it to {Assinafy::Support::WebhookVerifier}. Not available to OAuth
      # applications; use an API key or a user access token.
      #
      # @param endpoint_id [String]
      # @param account_id_override [String, nil]
      # @return [Hash] `{ secret: "whsec_..." }`
      # @raise [Assinafy::ApiError] `400` when signing is disabled; `404` on an unknown ID
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see GET /accounts/{account_id}/webhooks/endpoints/{endpoint_id}/secret
      # @example Read the signing secret
      #   client.webhooks.endpoint_secret('webhook-endpoint-id')
      #   # GET /accounts/{account_id}/webhooks/endpoints/webhook-endpoint-id/secret
      #   # => { secret: "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw" }
      def endpoint_secret(endpoint_id, account_id_override = nil)
        call('Failed to fetch webhook endpoint secret') do
          http_get("#{endpoint_path(endpoint_id, account_id_override)}/secret")
        end
      end

      # Replace an endpoint's signing secret. The old secret stops working
      # immediately, so update the receiver right away. Not available to OAuth
      # applications.
      #
      # @param endpoint_id [String]
      # @param account_id_override [String, nil]
      # @return [Hash] `{ secret: "whsec_..." }` (the new secret)
      # @raise [Assinafy::ApiError] `400` when signing is disabled; `404` on an unknown ID
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see POST /accounts/{account_id}/webhooks/endpoints/{endpoint_id}/secret/rotate
      # @example Rotate the signing secret
      #   client.webhooks.rotate_endpoint_secret('webhook-endpoint-id')
      #   # POST /accounts/{account_id}/webhooks/endpoints/webhook-endpoint-id/secret/rotate  (no request body)
      #   # => { secret: "whsec_new-secret-placeholder" }
      def rotate_endpoint_secret(endpoint_id, account_id_override = nil)
        path = endpoint_path(endpoint_id, account_id_override)

        @logger.info('Rotating webhook endpoint secret')

        call('Failed to rotate webhook endpoint secret') do
          http_post("#{path}/secret/rotate")
        end
      end

      private

      def endpoint_path(endpoint_id, account_id_override)
        eid = require_id(endpoint_id, 'Webhook endpoint ID')
        "accounts/#{account_id(account_id_override)}/webhooks/endpoints/#{eid}"
      end

      def webhook_body(payload, allowed, required)
        body = require_payload(payload, 'Webhook payload').transform_keys(&:to_sym)

        unknown = body.keys - allowed
        raise ValidationError.new("Unknown webhook fields: #{unknown.join(', ')}") unless unknown.empty?

        missing = required - body.keys
        raise ValidationError.new("Missing webhook fields: #{missing.join(', ')}") unless missing.empty?

        validate_webhook_fields!(body)
        body
      end

      def validate_webhook_fields!(body)
        require_string(body[:url], 'Webhook URL') if body.key?(:url)
        Utils.require_email(body[:email]) if body.key?(:email)
        require_string(body[:name], 'Webhook name') if body.key?(:name)
        %i[is_active signing_enabled].each { |key| require_boolean(body[key], key.to_s) if body.key?(key) }
        return unless body.key?(:events)

        events = require_array(body[:events], 'Webhook events')
        return if events.all? { |event| event.is_a?(String) && !event.strip.empty? }

        raise ValidationError.new('Webhook events must be non-empty Strings')
      end
    end
  end
end
