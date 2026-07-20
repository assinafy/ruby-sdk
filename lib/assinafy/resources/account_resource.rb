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
      # @return [Hash{Symbol=>Array,nil}] `{ data: [Account, ...], meta: nil }`
      #   (this endpoint sends no pagination headers)
      # @see GET /accounts
      # @example List my accounts
      #   # Request: GET /accounts
      #   client.accounts.list
      #
      #   # Response (unwrapped data payload):
      #   {
      #     data: [
      #       {
      #         'id' => '102d25a489f34a275d31a16045fd',
      #         'name' => 'MT',
      #         'roles' => ['owner'],
      #         'is_delete_allowed' => true,
      #         'created_at' => '2026-05-12T18:05:11Z'
      #       }
      #       # ... (one Hash per accessible account)
      #     ],
      #     meta: nil
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
      # @see POST /accounts
      # @example Create an account
      #   # Request: POST /accounts
      #   # Body: { "name": "Acme Inc." }
      #   client.accounts.create(name: 'Acme Inc.')
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'id' => '19f803b8a41d4b2fef372736a05',
      #     'name' => 'Acme Inc.',
      #     'primary_color' => nil,
      #     'secondary_color' => nil,
      #     'created_at' => '2026-07-20T15:53:33Z'
      #   }
      def create(payload)
        body = body_params(require_payload(payload, 'Account payload'))
        require_present(body['name'], 'name')

        call('Failed to create account') do
          http_post('accounts', body)
        end
      end

      # Fetch an account by ID (defaults to the client's account).
      #
      # @param account_id_override [String, nil]
      # @return [Hash] the account (envelope `data` unwrapped)
      # @see GET /accounts/{account_id}
      # @example Fetch the current account
      #   # Request: GET /accounts/{account_id}
      #   client.accounts.get
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'id' => '102d25a489f34a275d31a16045fd',
      #     'name' => 'MT',
      #     'primary_color' => nil,
      #     'secondary_color' => nil,
      #     'created_at' => '2026-05-12T18:05:11Z'
      #   }
      def get(account_id_override = nil)
        acc_id = account_id(account_id_override)

        call('Failed to fetch account') do
          http_get("accounts/#{acc_id}")
        end
      end

      # Update an account.
      #
      # @param payload [Hash] `name` and/or `notification_sender_type`
      # @param account_id_override [String, nil]
      # @return [Hash] the updated account (envelope `data` unwrapped)
      # @see PUT /accounts/{account_id}
      # @example Rename the current account
      #   # Request: PUT /accounts/{account_id}
      #   # Body: { "name": "Acme Renamed" }
      #   client.accounts.update(name: 'Acme Renamed')
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'id' => '19f803b8a41d4b2fef372736a05',
      #     'name' => 'Acme Renamed',
      #     'primary_color' => nil,
      #     'secondary_color' => nil,
      #     'created_at' => '2026-07-20T15:53:33Z'
      #   }
      def update(payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        body   = body_params(require_payload(payload, 'Account payload'))

        call('Failed to update account') do
          http_put("accounts/#{acc_id}", body)
        end
      end

      # Delete an account. Pass `force: true` to delete an account that still
      # owns documents.
      #
      # @param force [Boolean] force deletion (default false)
      # @param account_id_override [String, nil]
      # @return [nil] the API returns `data: []`; the SDK normalizes this to `nil`
      # @see DELETE /accounts/{account_id}
      # @example Force-delete a throwaway account
      #   # Request: DELETE /accounts/{account_id}
      #   # Body: { "force": true }
      #   client.accounts.delete(force: true, account_id_override: '19f803b8a41d4b2fef372736a05')
      #   # => nil
      def delete(force: false, account_id_override: nil)
        acc_id = account_id(account_id_override)

        call_void('Failed to delete account') do
          http_delete("accounts/#{acc_id}", body: body_params(force: force))
        end
      end

      # Fetch the account's public theme (name, brand colors, logo URL).
      #
      # @param account_id_override [String, nil]
      # @return [Hash] `{ 'account_name' =>, 'primary_color' =>, 'secondary_color' =>, 'logo' => }`
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
      # @note Documented in the API reference but not enabled on every
      #   environment — the sandbox currently returns 404 for this route.
      # @param granularity [String, nil] `"monthly"` or `"daily"`
      # @param month       [String, nil] e.g. `"2026-06"`
      # @param account_id_override [String, nil]
      # @return [Array<Hash>] one KPI entry per period
      # @see GET /accounts/{account_id}/stats
      # @example Fetch monthly KPIs
      #   # Request: GET /accounts/{account_id}/stats?granularity=monthly&month=2026-06
      #   client.accounts.stats(granularity: 'monthly', month: '2026-06')
      #
      #   # Response (unwrapped data payload), per the API reference:
      #   [
      #     {
      #       'period' => '2026-06', 'documents_uploaded' => 42, 'documents_sent' => 37,
      #       'signature_requests' => 61, 'documents_signed' => 52
      #       # ... (see docs for the full KPI series)
      #     }
      #   ]
      def stats(granularity: nil, month: nil, account_id_override: nil)
        acc_id = account_id(account_id_override)

        call('Failed to fetch account stats') do
          http_get("accounts/#{acc_id}/stats", query_params(granularity: granularity, month: month))
        end
      end

      # Download the account brand logo as raw image bytes.
      #
      # @param account_id_override [String, nil]
      # @return [String] binary image body (empty String when no logo is set)
      # @see GET /accounts/{account_id}/logo
      # @example Download the logo and save it
      #   # Request: GET /accounts/{account_id}/logo
      #   bytes = client.accounts.download_logo
      #   File.binwrite('logo.png', bytes)
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
      # @return [Hash] `{ 'mime_type' =>, 'version' =>, 'updated_at' => }`
      # @see POST /accounts/{account_id}/logo
      # @example Upload a PNG logo
      #   # Request: POST /accounts/{account_id}/logo (multipart/form-data)
      #   # Body: file=<binary image/png>
      #   client.accounts.upload_logo('/path/to/logo.png')
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'mime_type' => 'image/png',
      #     'version' => 1784562814,
      #     'updated_at' => '2026-07-20T15:53:35Z'
      #   }
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
      # @return [nil] the API returns `data: []`; the SDK normalizes this to `nil`
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
    end
  end
end
