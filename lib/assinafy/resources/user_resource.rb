# frozen_string_literal: true

module Assinafy
  module Resources
    # The authenticated user's own profile and cross-account KPIs.
    #
    # See https://api.assinafy.com.br/v1/docs for the User Object.
    class UserResource < BaseResource
      # Fetch the authenticated user's profile and the accounts they belong to.
      #
      # @return [Hash{String=>Object}] `{ 'user' => {..}, 'accounts' => [{..}] }`
      # @see GET /users/self
      # @example Fetch the current user
      #   # Request: GET /users/self
      #   client.users.me
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'user' => {
      #       'id' => 'md3j6p9w8b7y6qvqaoy5er42',
      #       'name' => 'Multica Test',
      #       'email' => 'bill@febacapital.com',
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
      #         'id' => '102d25a489f34a275d31a16045fd',
      #         'name' => 'MT',
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
      #   # Response (unwrapped data payload), per the API reference:
      #   [
      #     { 'period' => '2026-06', 'documents_uploaded' => 42, 'documents_signed' => 52 }
      #     # ... (see docs for the full KPI series)
      #   ]
      def stats(granularity: nil, month: nil)
        call('Failed to fetch user stats') do
          http_get('users/self/stats', query_params(granularity: granularity, month: month))
        end
      end
    end
  end
end
