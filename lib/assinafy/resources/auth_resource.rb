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
      # When the user has two-factor authentication enabled, the payload carries an `mfa_token`
      # instead of an access token; complete the login with #verify_mfa.
      #
      # @param email    [String]
      # @param password [String]
      # @return [Hash] unwrapped payload: { "access_token" => String, "user" => Hash, "accounts" => Array<Hash> },
      #   or a challenge carrying "mfa_token" when two-factor authentication is enabled
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
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      def login(email:, password:)
        Utils.require_email(email)
        require_string(password, 'Password')

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
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
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
        validate_provider!(provider, token)
        require_boolean(has_accepted_terms, 'has_accepted_terms')

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
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see POST /auth/link-social-login
      # @example Link a Google account
      #   client.auth.link_social_login(provider: 'google', token: 'provider-token')
      #   # Request body sent by the SDK:
      #   #   { "provider": "google", "token": "provider-token" }
      #   # Response: { "status": 200, "message": "Provider linked" }
      #   # => nil
      def link_social_login(provider:, token:)
        validate_provider!(provider, token)

        call_void('Failed to link social login') do
          http_post('auth/link-social-login', body_params(provider: provider, token: token))
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
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
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
        require_string(password, 'Password')

        call('Failed to create API key') do
          http_post('users/api-keys', body_params(password: password))
        end
      end

      # Retrieve the active API key for the authenticated user.
      #
      # For security the key is returned MASKED (only the last 4 characters are visible); the full key
      # is only available once, at #create_api_key time. Returns `nil` if no key has been generated yet.
      # This endpoint works with `X-Api-Key` authentication (verified live), not only a Bearer token.
      #
      # @return [Hash, nil] unwrapped payload: { "api_key" => String } (masked), or nil if no key exists yet
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
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
          http_get('users/api-keys')
        end
      end

      alias api_key get_api_key

      # Delete the API key of the authenticated user.
      #
      # The SDK ignores the response body and always returns `nil` on success. (The API itself
      # responds with an empty `data` payload.)
      #
      # @return [nil]
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
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
          http_delete('users/api-keys')
        end
      end

      # Change the authenticated user's password.
      #
      # @param email        [String]
      # @param password     [String] current password
      # @param new_password [String] the new password to set
      # @return [Hash] unwrapped payload: { "email" => String }
      #
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
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
        Utils.require_email(email)
        require_string(password, 'Password')
        require_string(new_password, 'New password')

        call('Failed to change password') do
          http_put(
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
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
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
        Utils.require_email(email)

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
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
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
        Utils.require_email(email)
        require_string(new_password, 'New password')
        require_string(token, 'Reset token') unless token.nil?

        call('Failed to reset password') do
          http_put(
            'authentication/reset-password',
            body_params(email: email, token: token, new_password: new_password),
            workspace_auth: false
          )
        end
      end

      # Complete a two-factor login. When the user has two-factor authentication enabled, #login
      # answers with an `mfa_token` challenge instead of an access token; exchange it here. The
      # challenge is single-use and expires 5 minutes after login.
      #
      # @param mfa_token [String] the challenge token returned by #login
      # @param code      [String] a 6-digit authenticator code, or a recovery code such as `ABCD-EFGH-JKMN`
      # @return [Hash] unwrapped payload, same shape as #login:
      #   { "access_token" => String, "user" => Hash, "accounts" => Array<Hash> }
      # @raise [Assinafy::ApiError] `400` on an invalid or used code; `401` when the challenge expired,
      #   was already used, or too many codes were tried
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see POST /authentication/mfa/verify
      #
      # @example Request and response
      #   session = resource.login(email: 'user@example.com', password: 'secret')
      #   resource.verify_mfa(mfa_token: session['mfa_token'], code: '123456') if session['mfa_token']
      #   # Request body sent by the SDK (no workspace credentials):
      #   #   { "mfa_token": "mfa-token-placeholder", "code": "123456" }
      #   #
      #   # Returns the unwrapped data payload:
      #   # {
      #   #   "access_token" => "access-token-placeholder",
      #   #   "user" => { "id" => "user-id", "name" => "Example User", ... },
      #   #   "accounts" => [{ "id" => "account-id", "name" => "Example Workspace", "roles" => ["owner"], ... }]
      #   # }
      def verify_mfa(mfa_token:, code:)
        require_string(mfa_token, 'MFA token')
        require_string(code, 'MFA code')

        call('Failed to verify two-factor code') do
          http_post('authentication/mfa/verify', body_params(mfa_token: mfa_token, code: code), workspace_auth: false)
        end
      end

      # List the authenticated user's enrolled two-factor methods and how many recovery codes remain.
      #
      # @return [Hash] unwrapped payload: { "methods" => Array<Hash>, "recovery_codes_remaining" => Integer }
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see GET /users/self/mfa
      #
      # @example Request and response
      #   resource.mfa_methods
      #   # No request body (GET).
      #   #
      #   # Returns the unwrapped data payload:
      #   # {
      #   #   "methods" => [
      #   #     { "id" => "mfa-method-id", "type" => "Totp", "label" => "My phone",
      #   #       "confirmed_at" => "2026-09-09T14:21:03Z", "last_used_at" => "2026-09-09T18:02:44Z" }
      #   #   ],
      #   #   "recovery_codes_remaining" => 8
      #   # }
      def mfa_methods
        call('Failed to list two-factor methods') do
          http_get('users/self/mfa')
        end
      end

      # Start authenticator (TOTP) enrollment. Returns the shared secret once; it cannot be read
      # again. Two-factor authentication stays off until #confirm_totp_enrollment succeeds.
      #
      # @param label [String, nil] a name to tell devices apart; omitted from the body when nil
      # @return [Hash] unwrapped payload: { "id" => String, "secret" => String, "provisioning_uri" => String }
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see POST /users/self/mfa/totp
      #
      # @example Request and response
      #   resource.start_totp_enrollment(label: 'My phone')
      #   # Request body sent by the SDK:
      #   #   { "label": "My phone" }
      #   #
      #   # Returns the unwrapped data payload (render provisioning_uri as a QR code):
      #   # {
      #   #   "id" => "mfa-method-id",
      #   #   "secret" => "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
      #   #   "provisioning_uri" => "otpauth://totp/user%40example.com?issuer=Assinafy&secret=GEZDGNBVGY3TQOJQ..."
      #   # }
      def start_totp_enrollment(label: nil)
        require_string(label, 'MFA label') unless label.nil?

        call('Failed to start authenticator enrollment') do
          http_post('users/self/mfa/totp', body_params(label: label))
        end
      end

      # Confirm authenticator enrollment with a live code from the new device. Returns the recovery
      # codes, shown only once. When a confirmed method of the same type already exists, confirming
      # replaces it and requires re-authentication with `password` or `reauth_code`.
      #
      # @param method_id   [String] the method ID returned by #start_totp_enrollment
      # @param code        [String] a live code from the new device
      # @param password    [String, nil] current password, when replacing an existing method
      # @param reauth_code [String, nil] a live code from the current device or a recovery code,
      #   when replacing an existing method
      # @return [Hash] unwrapped payload: { "recovery_codes" => Array<String> }
      # @raise [Assinafy::ApiError] `400` on an invalid code or missing re-authentication; `404` on an unknown ID
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see PUT /users/self/mfa/totp/confirm
      #
      # @example Request and response
      #   resource.confirm_totp_enrollment(method_id: 'mfa-method-id', code: '123456')
      #   # Request body sent by the SDK:
      #   #   { "id": "mfa-method-id", "code": "123456" }
      #   #
      #   # Returns the unwrapped data payload:
      #   # { "recovery_codes" => ["ABCD-EFGH-JKMN", "PQRS-TUVW-XYZ2", ...] }
      def confirm_totp_enrollment(method_id:, code:, password: nil, reauth_code: nil)
        require_string(method_id, 'MFA method ID')
        require_string(code, 'MFA code')
        require_string(password, 'Password') unless password.nil?
        require_string(reauth_code, 'Re-authentication code') unless reauth_code.nil?

        call('Failed to confirm authenticator enrollment') do
          http_put(
            'users/self/mfa/totp/confirm',
            body_params(id: method_id, code: code, password: password, reauth_code: reauth_code)
          )
        end
      end

      # Issue a fresh set of ten recovery codes, invalidating the previous set. Re-authenticate with
      # the current password or a `code` (a live authenticator code, or a recovery code, which is consumed).
      #
      # @param password [String, nil]
      # @param code     [String, nil]
      # @return [Hash] unwrapped payload: { "recovery_codes" => Array<String> }
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] when neither `password` nor `code` is given
      # @see POST /users/self/mfa/recovery-codes
      #
      # @example Request and response
      #   resource.regenerate_recovery_codes(code: '123456')
      #   # Request body sent by the SDK:
      #   #   { "code": "123456" }
      #   #
      #   # Returns the unwrapped data payload:
      #   # { "recovery_codes" => ["ABCD-EFGH-JKMN", ...] }
      def regenerate_recovery_codes(password: nil, code: nil)
        body = reauth_body(password, code)

        call('Failed to regenerate recovery codes') do
          http_post('users/self/mfa/recovery-codes', body)
        end
      end

      # Remove an enrolled two-factor method. Re-authenticate with the current password or a `code`
      # (a live authenticator code, or a recovery code, which is consumed). Removing the last method
      # also discards the recovery codes.
      #
      # @param method_id [String] the method ID from #mfa_methods
      # @param password  [String, nil]
      # @param code      [String, nil]
      # @return [Hash] unwrapped payload: { "is_mfa_enabled" => Boolean }
      # @raise [Assinafy::ApiError] on an unsuccessful API response; `404` on an unknown ID
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] when neither `password` nor `code` is given
      # @see DELETE /users/self/mfa/{customId}
      #
      # @example Request and response
      #   resource.delete_mfa_method('mfa-method-id', password: 'secret')
      #   # DELETE /users/self/mfa/mfa-method-id
      #   # Request body sent by the SDK:
      #   #   { "password": "secret" }
      #   #
      #   # Returns the unwrapped data payload:
      #   # { "is_mfa_enabled" => false }
      def delete_mfa_method(method_id, password: nil, code: nil)
        mid  = require_id(method_id, 'MFA method ID')
        body = reauth_body(password, code)

        call('Failed to remove two-factor method') do
          http_delete("users/self/mfa/#{mid}", body: body)
        end
      end

      private

      def reauth_body(password, code)
        if password.nil? && code.nil?
          raise ValidationError.new('Re-authentication requires a password or a two-factor code')
        end

        require_string(password, 'Password') unless password.nil?
        require_string(code, 'MFA code') unless code.nil?
        body_params(password: password, code: code)
      end

      def validate_provider!(provider, token)
        raise ValidationError.new('Provider must be google') unless provider == 'google'

        require_string(token, 'Provider token')
      end
    end
  end
end
