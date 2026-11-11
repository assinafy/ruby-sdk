# frozen_string_literal: true

module Assinafy
  module Resources
    # Accounts (workspaces): CRUD plus the per-account theme, KPI stats, and
    # brand logo (upload/download/delete).
    #
    # See https://api.assinafy.com.br/v1/docs for the Account Object and its
    # related endpoints.
    class AccountResource < BaseResource
      # List the accounts (workspaces) the authenticated user can access.
      #
      # @return [Hash{Symbol=>Array,nil}] `{ data: [Account, ...] }`
      #   (`meta` is omitted: this endpoint sends no pagination headers)
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see GET /accounts
      # @example List my accounts
      #   # Request: GET /accounts
      #   client.accounts.list
      #
      #   # Response (unwrapped data payload):
      #   {
      #     data: [
      #       {
      #         'id' => 'account-id',
      #         'name' => 'MT',
      #         'roles' => ['owner'],
      #         'is_delete_allowed' => true,
      #         'created_at' => '2026-05-12T18:05:11Z'
      #       }
      #       # ... (one Hash per accessible account)
      #     ]
      #   }
      def list
        call_list('Failed to list accounts') do
          http_get('accounts')
        end
      end

      # Create a new account (workspace).
      #
      # @param payload [Hash]
      # @option payload [String] :name                    required display name
      # @option payload [String] :notification_sender_type `"User"` or `"Account"`
      # @return [Hash] the created account (envelope `data` unwrapped)
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see POST /accounts
      # @example Create an account
      #   # Request: POST /accounts
      #   # Body: { "name": "Acme Inc." }
      #   client.accounts.create(name: 'Acme Inc.')
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'id' => 'account-id',
      #     'name' => 'Acme Inc.',
      #     'primary_color' => nil,
      #     'secondary_color' => nil,
      #     'created_at' => '2026-07-20T15:53:33Z'
      #   }
      def create(payload)
        body = body_params(require_payload(payload, 'Account payload'))
        require_string(body['name'], 'name')
        validate_sender_type!(body)

        call('Failed to create account') do
          http_post('accounts', body)
        end
      end

      # Fetch an account by ID (defaults to the client's account).
      # Pass `expand: 'signing_features'` to include current plan gates for signing.
      #
      # @param account_id_override [String, nil]
      # @return [Hash] the account (envelope `data` unwrapped)
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @param expand [String, nil] `signing_features` adds five boolean feature flags
      # @see GET /accounts/{account_id}
      # @example Fetch the current account
      #   # Request: GET /accounts/{account_id}
      #   client.accounts.get
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'id' => 'account-id',
      #     'name' => 'MT',
      #     'primary_color' => nil,
      #     'secondary_color' => nil,
      #     'limits' => { 'webhook_endpoints' => 1 },
      #     'created_at' => '2026-05-12T18:05:11Z'
      #   }
      def get(account_id_override = nil, expand: nil)
        acc_id = account_id(account_id_override)
        unless expand.nil? || expand == 'signing_features'
          raise ValidationError.new('expand must be signing_features')
        end

        call('Failed to fetch account') do
          http_get("accounts/#{acc_id}", { expand: expand })
        end
      end

      # Update an account.
      #
      # @param payload [Hash] `name` and/or `notification_sender_type`
      # @param account_id_override [String, nil]
      # @return [Hash] the updated account (envelope `data` unwrapped)
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see PUT /accounts/{account_id}
      # @example Rename the current account
      #   # Request: PUT /accounts/{account_id}
      #   # Body: { "name": "Acme Renamed" }
      #   client.accounts.update(name: 'Acme Renamed')
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'id' => 'account-id',
      #     'name' => 'Acme Renamed',
      #     'primary_color' => nil,
      #     'secondary_color' => nil,
      #     'created_at' => '2026-07-20T15:53:33Z'
      #   }
      def update(payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        body   = body_params(require_payload(payload, 'Account payload'))
        require_string(body['name'], 'name') if body.key?('name')
        validate_sender_type!(body)

        call('Failed to update account') do
          http_put("accounts/#{acc_id}", body)
        end
      end

      # Delete an account. Deletion is blocked while documents are pending.
      # For an active paid subscription, pass `force: true` to cancel the
      # subscription as part of deletion.
      #
      # @param force [Boolean] cancel an active paid subscription and continue
      #   deletion (default false); it does not bypass pending-document checks
      # @param account_id_override [String, nil]
      # @return [nil] the API returns `data: []`; the SDK normalizes this to `nil`
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see DELETE /accounts/{account_id}
      # @example Force-delete a throwaway account
      #   # Request: DELETE /accounts/{account_id}
      #   # Body: { "force": true }
      #   client.accounts.delete(force: true, account_id_override: 'account-id')
      #   # => nil
      def delete(force: false, account_id_override: nil)
        acc_id = account_id(account_id_override)
        force  = require_boolean(force, 'force')

        call_void('Failed to delete account') do
          http_delete("accounts/#{acc_id}", body: body_params(force: force))
        end
      end

      # Fetch the account's public theme (name, brand colors, logo URL).
      #
      # @param account_id_override [String, nil]
      # @return [Hash] `{ 'account_name' =>, 'primary_color' =>, 'secondary_color' =>, 'logo' => }`
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see GET /accounts/{account_id}/theme
      # @example Fetch the account theme
      #   # Request: GET /accounts/{account_id}/theme
      #   client.accounts.theme
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'account_name' => 'MT',
      #     'primary_color' => '2072b9',
      #     'secondary_color' => 'ffffff',
      #     'logo' => nil
      #   }
      def theme(account_id_override = nil)
        acc_id = account_id(account_id_override)

        call('Failed to fetch account theme') do
          http_get("accounts/#{acc_id}/theme")
        end
      end

      # Fetch per-account document KPIs.
      #
      # @note Documented in the API reference, but gated on the account's plan:
      #   this route answers 404 where the KPI feature is not enabled.
      # @param granularity [String, nil] `"monthly"` or `"daily"`
      # @param month       [String, nil] e.g. `"2026-06"`; required with daily granularity
      # @param account_id_override [String, nil]
      # @return [Array<Hash>] one KPI entry per period
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see GET /accounts/{account_id}/stats
      # @example Fetch monthly KPIs
      #   # Request: GET /accounts/{account_id}/stats?granularity=monthly&month=2026-06
      #   client.accounts.stats(granularity: 'monthly', month: '2026-06')
      #
      #   # Response (unwrapped data payload):
      #   [
      #     {
      #       'period' => '2026-06',
      #       'documents_uploaded' => 42,
      #       'documents_sent' => 37,
      #       'signature_requests' => 61,
      #       'signature_requests_notification_email' => 55,
      #       'signature_requests_notification_whatsapp' => 18,
      #       'signature_requests_notification_bypass' => 3,
      #       'signature_requests_verification_email' => 48,
      #       'signature_requests_verification_whatsapp' => 6,
      #       'signature_requests_verification_bypass' => 3,
      #       'signature_requests_verification_digital_certificate' => 4,
      #       'signature_requests_viewed' => 44,
      #       'signature_requests_completed' => 52,
      #       'documents_certified' => 30
      #     }
      #   ]
      def stats(granularity: nil, month: nil, account_id_override: nil)
        acc_id = account_id(account_id_override)
        query  = stats_params(granularity, month)

        call_array('Failed to fetch account stats') do
          http_get("accounts/#{acc_id}/stats", query)
        end
      end

      # Download the account brand logo as raw image bytes.
      #
      # @param account_id_override [String, nil]
      # @return [String] binary image body
      # @raise [Assinafy::ApiError] when no logo is configured (HTTP 404)
      # @see GET /accounts/{account_id}/logo
      # @example Download the logo and save it
      #   # Request: GET /accounts/{account_id}/logo
      #   bytes = client.accounts.download_logo
      #   File.binwrite('logo.png', bytes)
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      def download_logo(account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_binary('Failed to download account logo') do
          http_get("accounts/#{acc_id}/logo")
        end
      end

      # Upload (replace) the account brand logo.
      #
      # @param source [String, Hash] a path to an image, or a Hash with
      #   `:file_path` (path) **or** `:buffer` + `:file_name` (raw bytes).
      # @param account_id_override [String, nil]
      # @return [nil, Hash] `nil` for the OpenAPI's no-data envelope; the deployed
      #   API returns `{ 'mime_type' =>, 'version' =>, 'updated_at' => }`
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see POST /accounts/{account_id}/logo
      # @example Upload a PNG logo
      #   # Request: POST /accounts/{account_id}/logo (multipart/form-data)
      #   # Body: file=<binary image/png>
      #   client.accounts.upload_logo('/path/to/logo.png')
      #
      #   # Deployed-API response (unwrapped data payload):
      #   {
      #     'mime_type' => 'image/png',
      #     'version' => 1784562814,
      #     'updated_at' => '2026-07-20T15:53:35Z'
      #   }
      #   # => nil when the API returns the documented no-data envelope
      def upload_logo(source, account_id_override = nil)
        acc_id = account_id(account_id_override)
        buffer, file_name = read_source(source)

        call('Failed to upload account logo') do
          http_post("accounts/#{acc_id}/logo", { file: file_part(buffer, file_name) })
        end
      end

      # Delete the account brand logo.
      #
      # @param account_id_override [String, nil]
      # @return [nil] the documented success envelope has no `data` payload
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see DELETE /accounts/{account_id}/logo
      # @example Delete the logo
      #   # Request: DELETE /accounts/{account_id}/logo
      #   client.accounts.delete_logo
      #   # => nil
      def delete_logo(account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_void('Failed to delete account logo') do
          http_delete("accounts/#{acc_id}/logo")
        end
      end

      # Read the plan name, renewal date, document allowance and credit balance.
      # Billing data is unavailable to third-party OAuth applications.
      #
      # @param account_id_override [String, nil]
      # @return [Hash] AccountUsage
      # @raise [Assinafy::ValidationError] on an invalid account ID
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @see GET /accounts/{accountId}/usage
      # @example Read the workspace allowance
      #   client.accounts.usage
      #   # Request: GET /accounts/{accountId}/usage (no body)
      #   # => { 'plan' => 'Pro', 'documents_renewal_date' => '2026-12-01',
      #   #      'balances' => { 'documents' => { 'balance' => 90, 'limit' => 100, 'spent' => 10 },
      #   #                      'credits' => { 'balance' => 40, 'limit' => nil, 'spent' => 5 } } }
      def usage(account_id_override = nil)
        acc_id = account_id(account_id_override)
        call('Failed to fetch account usage') { http_get("accounts/#{acc_id}/usage") }
      end

      # Read workspace document-alert rules. `editable` identifies owners who can change them.
      # Third-party OAuth applications cannot access this policy.
      #
      # @param account_id_override [String, nil]
      # @return [Hash] NotificationPolicy with all event flags
      # @raise [Assinafy::ValidationError] on an invalid account ID
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @see GET /accounts/{accountId}/notification-policy
      # @example Read workspace notification rules
      #   client.accounts.notification_policy
      #   # Request: GET /accounts/{accountId}/notification-policy (no body)
      #   # => { 'editable' => true, 'owners_receive_all' => false, 'events' => {
      #   #   'DocumentCompleted' => true, 'SignerDeclined' => true, 'DocumentCancelled' => true,
      #   #   'DocumentAboutToExpire' => true, 'DocumentExpired' => true, 'DocumentExpirationReset' => true,
      #   #   'DocumentProcessingFailed' => true, 'TemplateProcessingFailed' => true,
      #   #   'SignerWhatsappFailed' => true, 'ContractRenewalNotice' => true, 'ContractExpiring' => true,
      #   #   'ContractExpired' => true, 'ContractRenewed' => true, 'SignerViewed' => false,
      #   #   'SignerSigned' => true, 'SignerIdentityReviewRequired' => true } }
      def notification_policy(account_id_override = nil)
        acc_id = account_id(account_id_override)
        call('Failed to fetch notification policy') { http_get("accounts/#{acc_id}/notification-policy") }
      end

      # Merge workspace notification rules. Only owners can write this policy.
      # Disabling identity-review alerts stops push only; its email is always sent.
      # Third-party OAuth applications cannot access this policy.
      #
      # @param payload [Hash] partial `events` map and/or boolean `owners_receive_all`
      # @param account_id_override [String, nil]
      # @return [Hash] the full NotificationPolicy shown by {#notification_policy}
      # @raise [Assinafy::ValidationError] on empty, unknown or invalid fields
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @see PUT /accounts/{accountId}/notification-policy
      # @example Stop signer-viewed alerts
      #   client.accounts.update_notification_policy(events: { SignerViewed: false }, owners_receive_all: true)
      #   # Request: PUT /accounts/{accountId}/notification-policy
      #   # Body: { "events": { "SignerViewed": false }, "owners_receive_all": true }
      #   # Response: the full policy from #notification_policy with owners_receive_all true.
      def update_notification_policy(payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        raw = require_payload(payload, 'Notification policy').transform_keys(&:to_s)
        validate_notification_policy!(raw)
        call('Failed to update notification policy') do
          http_put("accounts/#{acc_id}/notification-policy", body_params(raw))
        end
      end

      # List allowed embedding origins, oldest first. Requires embedded signing on the plan;
      # OAuth applications cannot manage origins.
      #
      # @param account_id_override [String, nil]
      # @return [Array<Hash>] EmbedOrigin objects
      # @raise [Assinafy::ValidationError] on an invalid account ID
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @see GET /accounts/{accountId}/embed-origins
      # @example List embedding origins
      #   client.accounts.list_embed_origins
      #   # Request: GET /accounts/{accountId}/embed-origins (no body)
      #   # => [{ 'id' => 'origin-id', 'origin' => 'https://app.example.com',
      #   #       'created_at' => '2026-11-04T12:05:00Z' }]
      def list_embed_origins(account_id_override = nil)
        acc_id = account_id(account_id_override)
        call_array('Failed to list embed origins') { http_get("accounts/#{acc_id}/embed-origins") }
      end

      # Allow an exact HTTPS origin to embed signing pages. HTTP is accepted only for localhost
      # and 127.0.0.1. At most ten origins are allowed; requires the plan feature and non-OAuth auth.
      #
      # @param origin [String] scheme://host[:port], optionally with a trailing slash
      # @param account_id_override [String, nil]
      # @return [Hash] created EmbedOrigin
      # @raise [Assinafy::ValidationError] on an invalid origin or account ID
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @see POST /accounts/{accountId}/embed-origins
      # @example Allow the application's origin
      #   client.accounts.create_embed_origin('https://app.example.com')
      #   # Request: POST /accounts/{accountId}/embed-origins
      #   # Body: { "origin": "https://app.example.com" }
      #   # => { 'id' => 'origin-id', 'origin' => 'https://app.example.com',
      #   #      'created_at' => '2026-11-04T12:05:00Z' }
      def create_embed_origin(origin, account_id_override = nil)
        acc_id = account_id(account_id_override)
        validate_embed_origin!(origin)
        call('Failed to create embed origin') do
          http_post("accounts/#{acc_id}/embed-origins", body_params(origin: origin))
        end
      end

      # Replace one allowed origin, retaining its ID. The same restrictions as {#create_embed_origin} apply.
      #
      # @param origin_id [String]
      # @param origin [String] exact allowed origin
      # @param account_id_override [String, nil]
      # @return [Hash] updated EmbedOrigin
      # @raise [Assinafy::ValidationError] on an invalid origin or ID
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @see PUT /accounts/{accountId}/embed-origins/{originId}
      # @example Replace an embedding origin
      #   client.accounts.update_embed_origin('origin-id', 'https://new.example.com')
      #   # Request: PUT /accounts/{accountId}/embed-origins/origin-id
      #   # Body: { "origin": "https://new.example.com" }
      #   # => { 'id' => 'origin-id', 'origin' => 'https://new.example.com',
      #   #      'created_at' => '2026-11-04T12:05:00Z' }
      def update_embed_origin(origin_id, origin, account_id_override = nil)
        acc_id = account_id(account_id_override)
        oid = require_id(origin_id, 'Origin ID')
        validate_embed_origin!(origin)
        call('Failed to update embed origin') do
          http_put("accounts/#{acc_id}/embed-origins/#{oid}", body_params(origin: origin))
        end
      end

      # Remove an allowed origin. Removing the last origin prevents new embed sessions.
      # Requires embedded signing on the plan; OAuth applications cannot manage origins.
      #
      # @param origin_id [String]
      # @param account_id_override [String, nil]
      # @return [nil] the empty success payload is discarded
      # @raise [Assinafy::ValidationError] on an invalid ID
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @see DELETE /accounts/{accountId}/embed-origins/{originId}
      # @example Stop allowing an origin
      #   client.accounts.delete_embed_origin('origin-id')
      #   # Request: DELETE /accounts/{accountId}/embed-origins/origin-id (no body)
      #   # Response data: []; SDK return: nil
      def delete_embed_origin(origin_id, account_id_override = nil)
        acc_id = account_id(account_id_override)
        oid = require_id(origin_id, 'Origin ID')
        call_void('Failed to delete embed origin') { http_delete("accounts/#{acc_id}/embed-origins/#{oid}") }
      end

      private

      def validate_notification_policy!(body)
        if body.empty? || (body.keys - %w[events owners_receive_all]).any?
          raise ValidationError.new('Notification policy requires events and/or owners_receive_all')
        end

        require_boolean(body['owners_receive_all'], 'owners_receive_all') if body.key?('owners_receive_all')
        return unless body.key?('events')

        events = require_payload(body['events'], 'Notification policy events')
        codes = UserResource::NOTIFICATION_PREFERENCE_CODES | UserResource::PUSH_PREFERENCE_CODES
        require_preferences(events, codes, 'Notification policy events') unless events.empty?
      end

      def validate_embed_origin!(origin)
        uri = URI.parse(require_string(origin, 'Embed origin'))
        secure = uri.is_a?(URI::HTTPS) || (uri.is_a?(URI::HTTP) && %w[localhost
                                                                      127.0.0.1].include?(uri.host.to_s.downcase))
        valid = secure && uri.host && !uri.host.include?('*') && (1..65_535).cover?(uri.port) &&
                ['', '/'].include?(uri.path) && !uri.userinfo && !uri.query && !uri.fragment
        return if valid

        raise ValidationError.new('Embed origin must be an exact HTTPS origin (HTTP is allowed only on localhost)')
      rescue URI::InvalidURIError
        raise ValidationError.new('Embed origin must be a valid origin URL')
      end

      def validate_sender_type!(body)
        return unless body.key?('notification_sender_type')
        return if %w[User Account].include?(body['notification_sender_type'])

        raise ValidationError.new('notification_sender_type must be User or Account')
      end
    end
  end
end
