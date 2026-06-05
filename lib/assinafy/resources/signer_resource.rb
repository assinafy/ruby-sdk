# frozen_string_literal: true

module Assinafy
  module Resources
    # Signer management. Covers both:
    #
    # - Account-scoped CRUD on signers (authenticated as a workspace user).
    # - Signer self-service endpoints (authenticated via `signer-access-code`).
    #
    # See https://api.assinafy.com.br/v1/docs#signer for the full
    # documentation of these endpoints.
    class SignerResource < BaseResource
      EMAIL_REGEX     = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/
      SIGNATURE_TYPES = %w[signature initial].freeze

      # Create a signer in the workspace.
      #
      # @param payload [Hash]
      # @option payload [String] :full_name             required
      # @option payload [String] :email                 optional, validated when present
      # @option payload [String] :whatsapp_phone_number optional
      # @option payload [String] :phone                 alias for :whatsapp_phone_number
      # @param account_id_override [String, nil]
      # @return [Hash] signer object (envelope `data` unwrapped)
      # @see POST /accounts/{account_id}/signers
      # @example Create a signer
      #   signer = client.signers.create(full_name: 'Audit Bill A2', email: 'bill@febacapital.com')
      #
      #   # Request body the SDK sends (nil/omitted optional fields are stripped):
      #   #   {
      #   #     "full_name": "Audit Bill A2",
      #   #     "email": "bill@febacapital.com"
      #   #   }
      #
      #   # => {
      #   #   "resource"              => "signer",
      #   #   "id"                    => "19e6b92e7895332ed9708535d8c",
      #   #   "full_name"             => "Audit Bill A2",
      #   #   "email"                 => "bill@febacapital.com",
      #   #   "whatsapp_phone_number" => nil,
      #   #   "has_accepted_terms"    => false
      #   # }
      def create(payload, account_id_override = nil)
        body   = signer_payload(payload, require_full_name: true)
        acc_id = account_id(account_id_override)

        @logger.info("Creating signer #{body['email'] || body['full_name']}")

        call('Failed to create signer') do
          http_post("accounts/#{acc_id}/signers", body)
        end
      end

      # Fetch a signer by ID.
      #
      # @param signer_id           [String]
      # @param account_id_override [String, nil]
      # @return [Hash] signer object (envelope `data` unwrapped)
      # @see GET /accounts/{account_id}/signers/{signer_id}
      # @example Fetch a signer by ID
      #   signer = client.signers.get('19e6b92e7895332ed9708535d8c')
      #
      #   # => {
      #   #   "resource"              => "signer",
      #   #   "id"                    => "19e6b92e7895332ed9708535d8c",
      #   #   "full_name"             => "Audit Bill A2",
      #   #   "email"                 => "bill@febacapital.com",
      #   #   "whatsapp_phone_number" => nil,
      #   #   "has_accepted_terms"    => false
      #   # }
      def get(signer_id, account_id_override = nil)
        acc_id = account_id(account_id_override)
        sid    = require_id(signer_id, 'Signer ID')

        call('Failed to fetch signer') do
          http_get("accounts/#{acc_id}/signers/#{sid}")
        end
      end

      # List signers in the workspace, with pagination metadata.
      #
      # @param params [Hash] query parameters (`search`, `sort`, `page`, `per_page`, ...)
      # @param account_id_override [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [...], meta: { ... } }`
      # @see GET /accounts/{account_id}/signers
      # @example List signers, page 1, 3 per page
      #   result = client.signers.list(page: 1, per_page: 3)
      #
      #   # => {
      #   #   data: [
      #   #     {
      #   #       "id"                    => "19e6b92e7895332ed9708535d8c",
      #   #       "full_name"             => "Audit Bill A2",
      #   #       "email"                 => "bill@febacapital.com",
      #   #       "whatsapp_phone_number" => nil,
      #   #       "has_accepted_terms"    => false
      #   #     }
      #   #     # ... (one Hash per signer)
      #   #   ],
      #   #   meta: { current_page: 1, per_page: 3, total: 4, last_page: 2 }
      #   # }
      def list(params = {}, account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_list('Failed to list signers') do
          http_get("accounts/#{acc_id}/signers", params)
        end
      end

      # Update a signer. Same payload shape as {#create} but with no required
      # fields. This is a PARTIAL update: fields you do not pass are omitted from
      # the request (left unchanged), not nulled out.
      #
      # @param signer_id           [String]
      # @param payload             [Hash]
      # @param account_id_override [String, nil]
      # @return [Hash] updated signer object (envelope `data` unwrapped)
      # @see PUT /accounts/{account_id}/signers/{signer_id}
      # @example Update a signer's full name (partial update — only full_name is sent)
      #   signer = client.signers.update('19e6b92e7895332ed9708535d8c', full_name: 'Audit Bill A3')
      #
      #   # Request body the SDK sends (omitted fields are not nulled):
      #   #   { "full_name": "Audit Bill A3" }
      #
      #   # => {
      #   #   "resource"              => "signer",
      #   #   "id"                    => "19e6b92e7895332ed9708535d8c",
      #   #   "full_name"             => "Audit Bill A3",
      #   #   "email"                 => "bill@febacapital.com",
      #   #   "whatsapp_phone_number" => nil,
      #   #   "has_accepted_terms"    => false
      #   # }
      def update(signer_id, payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        sid    = require_id(signer_id, 'Signer ID')
        body   = signer_payload(payload, require_full_name: false)

        call('Failed to update signer') do
          http_put("accounts/#{acc_id}/signers/#{sid}", body)
        end
      end

      # Delete a signer.
      #
      # @param signer_id           [String]
      # @param account_id_override [String, nil]
      # @return [nil] the SDK returns nil on success (response body is discarded)
      # @see DELETE /accounts/{account_id}/signers/{signer_id}
      # @example Delete a signer
      #   client.signers.delete('19e6b92e7895332ed9708535d8c')
      #   # => nil
      def delete(signer_id, account_id_override = nil)
        acc_id = account_id(account_id_override)
        sid    = require_id(signer_id, 'Signer ID')

        call_void('Failed to delete signer') do
          http_delete("accounts/#{acc_id}/signers/#{sid}")
        end
      end

      # Convenience: find a signer by email using the documented `search` query
      # parameter, then do a case-insensitive client-side match. Walks every
      # result page (using a fixed page size; the API clamps `per-page` to its
      # own maximum) until a match is found or the pages are exhausted. Returns
      # `nil` when no match is found (including on 404).
      #
      # @param email               [String]
      # @param account_id_override [String, nil]
      # @return [Hash, nil] the matching signer object, or nil when none matches
      # @example Find a signer by email
      #   signer = client.signers.find_by_email('bill@febacapital.com')
      #
      #   # Internally pages through GET /accounts/{account_id}/signers?search=...&per_page=50
      #   # and returns the single matching signer Hash (case-insensitive on email):
      #   # => {
      #   #   "id"                    => "19e6b92e7895332ed9708535d8c",
      #   #   "full_name"             => "Audit Bill A2",
      #   #   "email"                 => "bill@febacapital.com",
      #   #   "whatsapp_phone_number" => nil,
      #   #   "has_accepted_terms"    => false
      #   # }
      #   #
      #   # => nil # when no signer matches (including on a 404)
      def find_by_email(email, account_id_override = nil)
        assert_email!(email.to_s)
        target = email.to_s.downcase
        page   = 1

        loop do
          result = list({ search: email, page: page, per_page: 50 }, account_id_override)
          match  = result[:data].find { |signer| signer['email'].to_s.downcase == target }
          return match if match

          meta = result[:meta]
          break unless meta && meta[:current_page] && meta[:last_page] && meta[:current_page] < meta[:last_page]

          page += 1
        end

        nil
      rescue ApiError => e
        raise unless e.status_code == 404

        nil
      end

      # Fetch the authenticated signer's own profile (signer-access-code auth).
      #
      # @param signer_access_code [String]
      # @return [Hash] signer object plus self-only fields (envelope `data` unwrapped)
      # @see GET /signers/self
      # @example Fetch the signer's own profile
      #   me = client.signers.self_data(signer_access_code: '9uAWyOXx9hgzCKdCuahkinwvg8tWJ2RC')
      #
      #   # => {
      #   #   "resource"              => "signer",
      #   #   "id"                    => "uahkinwvg8tWJ2RC",
      #   #   "full_name"             => "Signer Name",
      #   #   "email"                 => "signer@example.com",
      #   #   "whatsapp_phone_number" => "+5548999990000",
      #   #   "has_accepted_terms"    => false,
      #   #   "has_signature"         => false, # self-only field
      #   #   "has_initial"           => false  # self-only field
      #   # }
      def self_data(signer_access_code:)
        call('Failed to fetch signer self') do
          http_get('signers/self', signer_access_code: signer_access_code)
        end
      end

      # Accept the platform's terms of use as the signer.
      #
      # @param signer_access_code [String]
      # @return [Hash] partial signer object reflecting the acceptance (envelope `data` unwrapped)
      # @see PUT /signers/accept-terms
      # @example Accept the terms of use
      #   result = client.signers.accept_terms(signer_access_code: '9uAWyOXx9hgzCKdCuahkinwvg8tWJ2RC')
      #
      #   # Request body the SDK sends:
      #   #   { "signer-access-code": "9uAWyOXx9hgzCKdCuahkinwvg8tWJ2RC" }
      #
      #   # => {
      #   #   "full_name"          => "Signer Name",
      #   #   "email"              => "signer@example.com",
      #   #   "has_accepted_terms" => true
      #   # }
      def accept_terms(signer_access_code:)
        call('Failed to accept signer terms') do
          http_put('signers/accept-terms', body_params(signer_access_code: signer_access_code))
        end
      end

      # Verify the signer's email with a one-time verification code.
      #
      # @param verification_code  [String]
      # @param signer_access_code [String]
      # @return [Hash] the raw response Hash; this endpoint sends no `data` envelope,
      #   so the body is returned verbatim (e.g. `{ "message" => "Code verified successfully" }`)
      # @see POST /verify
      # @example Verify the signer's email with a one-time code
      #   result = client.signers.verify_email(
      #     verification_code:  '123456',
      #     signer_access_code: '9uAWyOXx9hgzCKdCuahkinwvg8tWJ2RC'
      #   )
      #
      #   # Request body the SDK sends (note the hyphenated keys):
      #   #   {
      #   #     "verification-code": "123456",
      #   #     "signer-access-code": "9uAWyOXx9hgzCKdCuahkinwvg8tWJ2RC"
      #   #   }
      #
      #   # => { "message" => "Code verified successfully" }
      def verify_email(verification_code:, signer_access_code:)
        call('Failed to verify signer email') do
          http_post(
            'verify',
            body_params(
              verification_code:  verification_code,
              signer_access_code: signer_access_code
            )
          )
        end
      end

      # Confirm signer data (email/phone/terms) before signing a virtual assignment.
      #
      # @param document_id        [String]
      # @param payload            [Hash] `:email`, `:whatsapp_phone_number`,
      #                             `:has_accepted_terms` (all conditional)
      # @param signer_access_code [String]
      # @return [Hash] empty Hash `{}` on success (the endpoint returns no body)
      # @see PUT /documents/{documentId}/signers/confirm-data
      # @example Confirm data and accept terms in one call
      #   result = client.signers.confirm_data(
      #     'c57d51eaad68a7',
      #     { email: 'signer@example.com', whatsapp_phone_number: '+5548999990000', has_accepted_terms: true },
      #     signer_access_code: '9uAWyOXx9hgzCKdCuahkinwvg8tWJ2RC'
      #   )
      #
      #   # signer-access-code is sent as a query param; the JSON body the SDK sends:
      #   #   {
      #   #     "email": "signer@example.com",
      #   #     "whatsapp_phone_number": "+5548999990000",
      #   #     "has_accepted_terms": true
      #   #   }
      #
      #   # => {} # the endpoint returns an empty body on success
      def confirm_data(document_id, payload, signer_access_code:)
        doc_id = require_id(document_id, 'Document ID')
        body   = body_params(require_payload(payload))

        call('Failed to confirm signer data') do
          http_put("documents/#{doc_id}/signers/confirm-data", body,
                   signer_access_code: signer_access_code)
        end
      end

      # Upload the signer's signature image. The request body is raw image bytes.
      #
      # @param content            [String] raw image bytes
      # @param signer_access_code [String]
      # @param type               [String] `signature` or `initial`
      # @param content_type       [String] e.g. `image/png`
      # @return [Array] empty Array `[]` on success (envelope `data` unwrapped)
      # @see POST /signature
      # @example Upload a PNG signature image
      #   bytes  = File.binread('signature.png')
      #   result = client.signers.upload_signature(
      #     bytes,
      #     signer_access_code: '9uAWyOXx9hgzCKdCuahkinwvg8tWJ2RC',
      #     type:               'signature',
      #     content_type:       'image/png'
      #   )
      #
      #   # The SDK sends the RAW image bytes as the body, with
      #   # Content-Type: image/png and ?signer-access-code=...&type=signature query params.
      #
      #   # => [] # the envelope data is an empty Array on success
      def upload_signature(content, signer_access_code:, type: 'signature', content_type: 'image/png')
        sig_type = signature_type(type)

        call('Failed to upload signer signature') do
          @connection.post('signature') do |request|
            request.params.update(query_params(signer_access_code: signer_access_code, type: sig_type))
            request.headers['Content-Type'] = content_type
            request.body = content
          end
        end
      end

      # Download the signer's signature image as raw bytes.
      #
      # @param signer_access_code [String]
      # @param type               [String] `signature` or `initial`
      # @return [String] binary image body (ASCII-8BIT), e.g. raw PNG bytes
      # @see GET /signature/{type}
      # @example Download and save the signer's signature image
      #   png = client.signers.download_signature(
      #     signer_access_code: '9uAWyOXx9hgzCKdCuahkinwvg8tWJ2RC',
      #     type:               'signature'
      #   )
      #
      #   # The SDK returns the raw response body as binary bytes (Content-Type: image/png):
      #   # => "\x89PNG\r\n\x1A\n..." # ASCII-8BIT String
      #   File.binwrite('signature.png', png)
      def download_signature(signer_access_code:, type: 'signature')
        sig_type = signature_type(type)

        call_binary('Failed to download signer signature') do
          http_get("signature/#{sig_type}", signer_access_code: signer_access_code)
        end
      end

      private

      def assert_email!(email)
        unless email && EMAIL_REGEX.match?(email)
          raise ValidationError.new('Invalid email address', { email: email })
        end
      end

      def signer_payload(payload, require_full_name:)
        raw = require_payload(payload, 'Signer payload')
        p   = raw.transform_keys(&:to_s)

        full_name = p['full_name'] || p['name']
        raise ValidationError.new('full_name is required') if require_full_name && full_name.to_s.strip.empty?

        email = p['email']
        assert_email!(email) if email && !email.to_s.empty?

        body_params(
          full_name:             full_name,
          email:                 email,
          whatsapp_phone_number: p['whatsapp_phone_number'] || p['phone']
        )
      end

      def signature_type(type)
        value = require_id(type, 'Signature type').to_s
        return value if SIGNATURE_TYPES.include?(value)

        raise ValidationError.new('Signature type must be signature or initial', { type: type })
      end
    end
  end
end
