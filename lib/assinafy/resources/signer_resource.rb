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
      # @return [Hash] signer object
      # @see POST /accounts/{account_id}/signers
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
      # @return [Hash]
      # @see GET /accounts/{account_id}/signers/{signer_id}
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
      def list(params = {}, account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_list('Failed to list signers') do
          http_get("accounts/#{acc_id}/signers", params)
        end
      end

      # Update a signer. Same payload shape as {#create} but with no required fields.
      #
      # @param signer_id           [String]
      # @param payload             [Hash]
      # @param account_id_override [String, nil]
      # @return [Hash]
      # @see PUT /accounts/{account_id}/signers/{signer_id}
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
      # @return [nil]
      # @see DELETE /accounts/{account_id}/signers/{signer_id}
      def delete(signer_id, account_id_override = nil)
        acc_id = account_id(account_id_override)
        sid    = require_id(signer_id, 'Signer ID')

        call_void('Failed to delete signer') do
          http_delete("accounts/#{acc_id}/signers/#{sid}")
        end
      end

      # Convenience: find a signer by email using the documented `search` query
      # parameter, then do a case-insensitive client-side match. Returns `nil`
      # when no match is found (including on 404).
      #
      # @param email               [String]
      # @param account_id_override [String, nil]
      # @return [Hash, nil]
      def find_by_email(email, account_id_override = nil)
        assert_email!(email.to_s)
        target = email.to_s.downcase

        result = list({ search: email, per_page: 100 }, account_id_override)
        result[:data].find { |signer| signer['email'].to_s.downcase == target }
      rescue ApiError => e
        raise unless e.status_code == 404

        nil
      end

      # Fetch the authenticated signer's own profile (signer-access-code auth).
      #
      # @param signer_access_code [String]
      # @return [Hash]
      # @see GET /signers/self
      def self_data(signer_access_code:)
        call('Failed to fetch signer self') do
          http_get('signers/self', signer_access_code: signer_access_code)
        end
      end

      # Accept the platform's terms of use as the signer.
      #
      # @param signer_access_code [String]
      # @return [Hash]
      # @see PUT /signers/accept-terms
      def accept_terms(signer_access_code:)
        call('Failed to accept signer terms') do
          http_put('signers/accept-terms', body_params(signer_access_code: signer_access_code))
        end
      end

      # Verify the signer's email with a one-time verification code.
      #
      # @param verification_code  [String]
      # @param signer_access_code [String]
      # @return [Hash]
      # @see POST /verify
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
      # @return [Hash]
      # @see PUT /documents/{documentId}/signers/confirm-data
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
      # @return [Hash]
      # @see POST /signature
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
      # @return [String] binary image body
      # @see GET /signature/{type}
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
