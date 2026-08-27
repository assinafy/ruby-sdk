# frozen_string_literal: true

module Assinafy
  module Resources
    # Authentication and API key management.
    #
    # See https://api.assinafy.com.br/v1/docs#authentication for the full
    # documentation of these endpoints.
    class AuthResource < BaseResource
      # Authenticate with email and password.
      #
      # The returned `access_token` is a JWT that typically expires in one hour. For long-lived
      # back-end integrations, prefer an API key (see #create_api_key) over the access token.
      #
      # @param email    [String]
      # @param password [String]
      # @return [Hash] unwrapped payload: { "access_token" => String, "user" => Hash, "accounts" => Array<Hash> }
      # @raise [Assinafy::ApiError] on a non-2xx response
      #
      # @see POST /login
      #
      # @example Request and response
      #   resource.login(email: 'user@example.com', password: 'secret')
      #   # Request body sent by the SDK:
      #   #   { "email": "user@example.com", "password": "secret" }
      #   #
      #   # Returns the unwrapped data payload (envelope { status, message, data } stripped):
      #   # {
      #   #   "access_token" => "access-token-placeholder",
      #   #   "user" => {
      #   #     "id" => "user-id", "name" => "Example User",
      #   #     "email" => "user@example.com", "telephone" => "+15555550100",
      #   #     "government_id" => "00000000000", "is_email_verified" => false,
      #   #     "has_accepted_terms" => true, "created_at" => "2023-03-03T11:51:34Z",
      #   #     "to_be_deleted_at" => nil
      #   #   },
      #   #   "accounts" => [
      #   #     { "id" => "account-id", "name" => "Example Workspace", "roles" => ["owner"],
      #   #       "is_delete_allowed" => true, "created_at" => "2023-03-03T11:51:34Z" }
      #   #   ]
      #   # }
      def login(email:, password:)
        call('Failed to login') do
          http_post('login', body_params(email: email, password: password), workspace_auth: false)
        end
      end

      # Authenticate with a third-party identity provider token.
      #
      # Currently the only supported provider is `google`. Returns the same shape as #login.
      #
      # @param provider           [String] the provider type; currently only `google`
      # @param token              [String] provider-issued OAuth/OIDC access or ID token
      # @param has_accepted_terms [Boolean]
      # @return [Hash] unwrapped payload: { "access_token" => String, "user" => Hash, "accounts" => Array<Hash> }
      #
      # @see POST /authentication/social-login
      #
      # @example Request and response
      #   resource.social_login(provider: 'google', token: 'provider-token', has_accepted_terms: true)
      #   # Request body sent by the SDK:
      #   #   { "provider": "google", "token": "provider-token", "has_accepted_terms": true }
      #   #
      #   # Returns the unwrapped data payload (envelope stripped); same shape as #login:
      #   # {
      #   #   "access_token" => "access-token-placeholder",
      #   #   "user" => { "id" => "user-id", "name" => "Example User", ... },
      #   #   "accounts" => [
      #   #     { "id" => "account-id", "name" => "Example Workspace", "roles" => ["owner"],
      #   #       "is_delete_allowed" => true, "created_at" => "2023-03-03T11:51:34Z" }
      #   #   ]
      #   # }
      def social_login(provider:, token:, has_accepted_terms:)
        call('Failed to login with social provider') do
          http_post(
            'authentication/social-login',
            body_params(
              provider:           provider,
              token:              token,
              has_accepted_terms: has_accepted_terms
            ),
            workspace_auth: false
          )
        end
      end

      # Link a third-party identity provider to the authenticated user's account.
      #
      # @param provider [String] the provider type; currently only `google`
      # @param token    [String] provider-issued OAuth/OIDC token
      # @return [nil] the documented success envelope has no `data` payload
      # @see POST /auth/link-social-login
      # @example Link a Google account
      #   client.auth.link_social_login(provider: 'google', token: 'provider-token')
      #   # Request body sent by the SDK:
      #   #   { "provider": "google", "token": "provider-token" }
      #   # Response: { "status": 200, "message": "Provider linked" }
      #   # => nil
      def link_social_login(provider:, token:)
        call('Failed to link social login') do
          @connection.post('auth/link-social-login', body_params(provider: provider, token: token))
        end
      end

      # Generate a new API key for the authenticated user.
      #
      # The returned key is shown in full only once, here; afterwards #get_api_key returns a masked
      # version. IMPORTANT: generating a new key deletes (invalidates) the previous one. Send the key
      # via the `X-Api-Key` header and never expose it in a front-end application.
      #
      # @param password [String] the user's current password
      # @return [Hash] unwrapped payload: { "api_key" => String } (the new key, in full)
      #
      # @see POST /users/api-keys
      #
      # @example Request and response
      #   resource.create_api_key(password: 'secret')
      #   # Request body sent by the SDK:
      #   #   { "password": "secret" }
      #   #
      #   # Returns the unwrapped data payload (envelope stripped):
      #   # { "api_key" => "api-key-created-once" }
      def create_api_key(password:)
        call('Failed to create API key') do
          @connection.post('users/api-keys', body_params(password: password))
        end
      end

      # Retrieve the active API key for the authenticated user.
      #
      # For security the key is returned MASKED (only the last 4 characters are visible); the full key
      # is only available once, at #create_api_key time. Returns `nil` if no key has been generated yet.
      # This endpoint works with `X-Api-Key` authentication (verified live), not only a Bearer token.
      #
      # @return [Hash, nil] unwrapped payload: { "api_key" => String } (masked), or nil if no key exists yet
      # @see GET /users/api-keys
      #
      # @example Request and response (key exists)
      #   resource.get_api_key
      #   # No request body (GET).
      #   #
      #   # Returns the unwrapped data payload (envelope stripped):
      #   # { "api_key" => "************************************************************9Jdr" }
      #
      # @example Response when no key has been generated yet
      #   resource.get_api_key # => nil
      def get_api_key
        call('Failed to get API key') do
          @connection.get('users/api-keys')
        end
      end

      alias api_key get_api_key

      # Delete the API key of the authenticated user.
      #
      # The SDK ignores the response body and always returns `nil` on success. (The API itself
      # responds with an empty `data` payload.)
      #
      # @return [nil]
      # @see DELETE /users/api-keys
      #
      # @example Request and response
      #   resource.delete_api_key
      #   # No request body (DELETE).
      #   #
      #   # Returns nil on success (the API's empty `data` payload is discarded).
      #   # => nil
      def delete_api_key
        call_void('Failed to delete API key') do
          @connection.delete('users/api-keys')
        end
      end

      # Change the authenticated user's password.
      #
      # @param email        [String]
      # @param password     [String] current password
      # @param new_password [String] the new password to set
      # @return [Hash] unwrapped payload: { "email" => String }
      #
      # @see PUT /authentication/change-password
      #
      # @example Request and response
      #   resource.change_password(email: 'user@example.com', password: 'current-password',
      #                            new_password: 'new-password')
      #   # Request body sent by the SDK:
      #   #   { "email": "user@example.com", "password": "current-password",
      #   #     "new_password": "new-password" }
      #   #
      #   # Returns the unwrapped data payload (envelope stripped):
      #   # { "email" => "user@example.com" }
      def change_password(email:, password:, new_password:)
        call('Failed to change password') do
          @connection.put(
            'authentication/change-password',
            body_params(email: email, password: password, new_password: new_password)
          )
        end
      end

      # Trigger a password-reset email for the given account.
      #
      # Used when the user forgot their password or has not set one yet. An email with a reset token
      # is sent; pass that token to #reset_password to complete the flow.
      #
      # @param email [String]
      # @return [Hash] unwrapped payload: { "email" => String }
      #
      # @see PUT /authentication/request-password-reset
      #
      # @example Request and response
      #   resource.request_password_reset(email: 'user@example.com')
      #   # Request body sent by the SDK:
      #   #   { "email": "user@example.com" }
      #   #
      #   # Returns the unwrapped data payload (envelope stripped):
      #   # { "email" => "user@example.com" }
      def request_password_reset(email:)
        call('Failed to request password reset') do
          http_put('authentication/request-password-reset', body_params(email: email), workspace_auth: false)
        end
      end

      # Reset the password using the token sent via #request_password_reset.
      #
      # @param email        [String]
      # @param new_password [String] the new password to set
      # @param token        [String, nil] reset token from the email; omitted from the body when nil
      # @return [Hash] unwrapped payload: { "email" => String }
      #
      # @see PUT /authentication/reset-password
      #
      # @example Request and response
      #   resource.reset_password(email: 'user@example.com', new_password: 'new-password',
      #                           token: 'reset-token')
      #   # Request body sent by the SDK (nil token would be omitted by body_params):
      #   #   { "email": "user@example.com", "token": "reset-token", "new_password": "new-password" }
      #   #
      #   # Returns the unwrapped data payload (envelope stripped):
      #   # { "email" => "user@example.com" }
      def reset_password(email:, new_password:, token: nil)
        call('Failed to reset password') do
          http_put(
            'authentication/reset-password',
            body_params(email: email, token: token, new_password: new_password),
            workspace_auth: false
          )
        end
      end
    end
  end
end
