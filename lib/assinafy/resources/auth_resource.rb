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
      # @param email    [String]
      # @param password [String]
      # @return [Hash] payload containing an `access_token` and user info
      # @raise [Assinafy::ApiError] on a non-2xx response
      #
      # @see POST /login
      def login(email:, password:)
        call('Failed to login') do
          @connection.post('login', body_params(email: email, password: password))
        end
      end

      # Authenticate with a third-party identity provider token.
      #
      # @param provider           [String] e.g. `google`, `apple`
      # @param token              [String] provider-issued OAuth/OIDC token
      # @param has_accepted_terms [Boolean]
      # @return [Hash]
      #
      # @see POST /authentication/social-login
      def social_login(provider:, token:, has_accepted_terms:)
        call('Failed to login with social provider') do
          @connection.post(
            'authentication/social-login',
            body_params(
              provider:           provider,
              token:              token,
              has_accepted_terms: has_accepted_terms
            )
          )
        end
      end

      # Generate a new API key for the authenticated user.
      #
      # @param password [String] the user's current password
      # @return [Hash] payload containing the new `api_key`
      #
      # @see POST /users/api-keys
      def create_api_key(password:)
        call('Failed to create API key') do
          @connection.post('users/api-keys', body_params(password: password))
        end
      end

      # Retrieve the active API key for the authenticated user.
      #
      # @return [Hash]
      # @see GET /users/api-keys
      def get_api_key
        call('Failed to get API key') do
          @connection.get('users/api-keys')
        end
      end

      alias api_key get_api_key

      # Delete the API key of the authenticated user.
      #
      # @return [nil]
      # @see DELETE /users/api-keys
      def delete_api_key
        call_void('Failed to delete API key') do
          @connection.delete('users/api-keys')
        end
      end

      # Change the authenticated user's password.
      #
      # @param email        [String]
      # @param password     [String] current password
      # @param new_password [String]
      # @return [Hash]
      #
      # @see PUT /authentication/change-password
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
      # @param email [String]
      # @return [Hash]
      #
      # @see PUT /authentication/request-password-reset
      def request_password_reset(email:)
        call('Failed to request password reset') do
          @connection.put('authentication/request-password-reset', body_params(email: email))
        end
      end

      # Reset the password using the token sent via #request_password_reset.
      #
      # @param email        [String]
      # @param new_password [String]
      # @param token        [String, nil] reset token from the email
      # @return [Hash]
      #
      # @see PUT /authentication/reset-password
      def reset_password(email:, new_password:, token: nil)
        call('Failed to reset password') do
          @connection.put(
            'authentication/reset-password',
            body_params(email: email, token: token, new_password: new_password)
          )
        end
      end
    end
  end
end
