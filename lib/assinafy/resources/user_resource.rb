# frozen_string_literal: true

module Assinafy
  module Resources
    # The authenticated user's own profile and cross-account KPIs.
    #
    # See https://api.assinafy.com.br/v1/docs for the User Object.
    class UserResource < BaseResource
      NOTIFICATION_PREFERENCE_CODES = %w[
        DocumentCompleted
        SignerDeclined
        DocumentCancelled
        DocumentAboutToExpire
        DocumentExpired
        DocumentExpirationReset
        DocumentProcessingFailed
        TemplateProcessingFailed
        SignerWhatsappFailed
      ].freeze

      # Fetch the authenticated user's profile. The current OpenAPI response is
      # an `AuthUser` directly, while some sandbox deployments return the login-like
      # `{ 'user' => AuthUser, 'accounts' => [...] }` shape. The SDK does not reshape
      # either form; it returns the envelope's `data` value unchanged.
      #
      # @return [Hash{String=>Object}] an AuthUser Hash, or the sandbox
      #   `{ 'user' => {..}, 'accounts' => [{..}] }` form
      # @see GET /users/self
      # @example Fetch the current user
      #   # Request: GET /users/self
      #   client.users.me
      #
      #   # Current OpenAPI response (unwrapped data payload):
      #   {
      #     'id' => 'user-id',
      #     'name' => 'Example User',
      #     'email' => 'user@example.com',
      #     'telephone' => nil,
      #     'government_id' => '',
      #     'is_email_verified' => true,
      #     'has_accepted_terms' => true,
      #     'is_password_set' => true,
      #     'created_at' => '2026-05-12T18:05:11Z',
      #     'to_be_deleted_at' => nil
      #   }
      #
      #   # Shape returned by some sandbox deployments (also passed through unchanged):
      #   {
      #     'user' => {
      #       'id' => 'user-id',
      #       'name' => 'Example User',
      #       'email' => 'user@example.com',
      #       'telephone' => nil,
      #       'government_id' => '',
      #       'is_email_verified' => true,
      #       'has_accepted_terms' => true,
      #       'is_password_set' => true,
      #       'created_at' => '2026-05-12T18:05:11Z',
      #       'to_be_deleted_at' => nil
      #     },
      #     'accounts' => [
      #       {
      #         'id' => 'account-id',
      #         'name' => 'Example Workspace',
      #         'roles' => ['owner'],
      #         'is_delete_allowed' => true,
      #         'created_at' => '2026-05-12T18:05:11Z'
      #       }
      #     ]
      #   }
      def me
        call('Failed to fetch current user') do
          http_get('users/self')
        end
      end

      # Fetch the authenticated user's cross-account document KPIs.
      #
      # @note Documented in the API reference but not enabled on every
      #   environment — the sandbox currently returns 404 for this route.
      # @param granularity [String, nil] `"monthly"` or `"daily"`
      # @param month       [String, nil] e.g. `"2026-06"`
      # @return [Array<Hash>] one KPI entry per period
      # @see GET /users/self/stats
      # @example Fetch monthly cross-account KPIs
      #   # Request: GET /users/self/stats?granularity=monthly
      #   client.users.stats(granularity: 'monthly')
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
      def stats(granularity: nil, month: nil)
        call_array('Failed to fetch user stats') do
          http_get('users/self/stats', query_params(granularity: granularity, month: month))
        end
      end

      # Fetch all owner-facing document email preferences. All nine keys are
      # returned and default to true. Account and security email is not
      # configurable through this endpoint.
      #
      # @return [Hash{String=>Boolean}] all nine documented preference codes
      # @see GET /users/self/notification-preferences
      # @example Fetch the current preferences
      #   # Request: GET /users/self/notification-preferences
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'DocumentCompleted' => true,
      #     'SignerDeclined' => true,
      #     'DocumentCancelled' => true,
      #     'DocumentAboutToExpire' => true,
      #     'DocumentExpired' => true,
      #     'DocumentExpirationReset' => true,
      #     'DocumentProcessingFailed' => true,
      #     'TemplateProcessingFailed' => true,
      #     'SignerWhatsappFailed' => true
      #   }
      def notification_preferences
        call('Failed to fetch notification preferences') do
          http_get('users/self/notification-preferences')
        end
      end

      # Merge selected owner-facing document email preferences.
      #
      # Omitted keys keep their current values. The API returns the full
      # nine-key map shown by {#notification_preferences}.
      #
      # @param preferences [Hash{String,Symbol=>Boolean}] non-empty partial map
      # @return [Hash{String=>Boolean}] the full updated map
      # @see PUT /users/self/notification-preferences
      # @example Disable one notification
      #   client.users.update_notification_preferences(SignerDeclined: false)
      #
      #   # Request: PUT /users/self/notification-preferences
      #   # Body: { "SignerDeclined": false }
      #
      #   # Response (the full unwrapped preference map):
      #   {
      #     'DocumentCompleted' => true,
      #     'SignerDeclined' => false,
      #     'DocumentCancelled' => true,
      #     'DocumentAboutToExpire' => true,
      #     'DocumentExpired' => true,
      #     'DocumentExpirationReset' => true,
      #     'DocumentProcessingFailed' => true,
      #     'TemplateProcessingFailed' => true,
      #     'SignerWhatsappFailed' => true
      #   }
      def update_notification_preferences(preferences)
        preferences = require_payload(preferences, 'Notification preferences')
        raise ValidationError.new('At least one notification preference is required') if preferences.empty?

        preferences.each do |code, enabled|
          code = code.to_s
          unless NOTIFICATION_PREFERENCE_CODES.include?(code)
            raise ValidationError.new("Unknown notification preference: #{code}")
          end
          unless [true, false].include?(enabled)
            raise ValidationError.new("Notification preference #{code} must be boolean")
          end
        end

        call('Failed to update notification preferences') do
          http_put('users/self/notification-preferences', body_params(preferences))
        end
      end
    end
  end
end
