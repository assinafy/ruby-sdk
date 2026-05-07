# frozen_string_literal: true

module Assinafy
  module Resources
    class AuthResource < BaseResource
      def login(email:, password:)
        call('Failed to login') do
          @connection.post('login', body_params(email: email, password: password))
        end
      end

      def social_login(provider:, token:, has_accepted_terms:)
        call('Failed to login with social provider') do
          @connection.post(
            'authentication/social-login',
            body_params(
              provider: provider,
              token: token,
              has_accepted_terms: has_accepted_terms
            )
          )
        end
      end

      def create_api_key(password:)
        call('Failed to create API key') do
          @connection.post('users/api-keys', body_params(password: password))
        end
      end

      def get_api_key
        call('Failed to get API key') do
          @connection.get('users/api-keys')
        end
      end

      alias api_key get_api_key

      def delete_api_key
        call_void('Failed to delete API key') do
          @connection.delete('users/api-keys')
        end
      end

      def change_password(email:, password:, new_password:)
        call('Failed to change password') do
          @connection.put(
            'authentication/change-password',
            body_params(email: email, password: password, new_password: new_password)
          )
        end
      end

      def request_password_reset(email:)
        call('Failed to request password reset') do
          @connection.put('authentication/request-password-reset', body_params(email: email))
        end
      end

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
