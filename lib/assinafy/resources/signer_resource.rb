# frozen_string_literal: true

module Assinafy
  module Resources
    class SignerResource < BaseResource
      EMAIL_REGEX = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/
      SIGNATURE_TYPES = %w[signature initial].freeze

      def create(payload, account_id_override = nil)
        body   = signer_payload(payload, require_full_name: true)
        acc_id = account_id(account_id_override)

        @logger.info("Creating signer #{body['email'] || body['full_name']}")

        call('Failed to create signer') do
          http_post("accounts/#{acc_id}/signers", body)
        end
      end

      def get(signer_id, account_id_override = nil)
        acc_id = account_id(account_id_override)
        sid    = require_id(signer_id, 'Signer ID')

        call('Failed to fetch signer') do
          http_get("accounts/#{acc_id}/signers/#{sid}")
        end
      end

      def list(params = {}, account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_list('Failed to list signers') do
          http_get("accounts/#{acc_id}/signers", params)
        end
      end

      def update(signer_id, payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        sid    = require_id(signer_id, 'Signer ID')
        body   = signer_payload(payload, require_full_name: false)

        call('Failed to update signer') do
          http_put("accounts/#{acc_id}/signers/#{sid}", body)
        end
      end

      def delete(signer_id, account_id_override = nil)
        acc_id = account_id(account_id_override)
        sid    = require_id(signer_id, 'Signer ID')

        call_void('Failed to delete signer') do
          http_delete("accounts/#{acc_id}/signers/#{sid}")
        end
      end

      def find_by_email(email, account_id_override = nil)
        assert_email!(email.to_s)
        target = email.to_s.downcase

        result = list({ search: email, per_page: 100 }, account_id_override)
        result[:data].find { |signer| signer['email'].to_s.downcase == target }
      rescue ApiError => e
        raise unless e.status_code == 404

        nil
      end

      def self_data(signer_access_code:)
        call('Failed to fetch signer self') do
          http_get('signers/self', signer_access_code: signer_access_code)
        end
      end

      def accept_terms(signer_access_code:)
        call('Failed to accept signer terms') do
          http_put('signers/accept-terms', body_params(signer_access_code: signer_access_code))
        end
      end

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

      def confirm_data(document_id, payload, signer_access_code:)
        doc_id = require_id(document_id, 'Document ID')
        body   = body_params(require_payload(payload))

        call('Failed to confirm signer data') do
          http_put("documents/#{doc_id}/signers/confirm-data", body,
                   signer_access_code: signer_access_code)
        end
      end

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
