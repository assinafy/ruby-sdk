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
      EMAIL_REGEX     = Utils::EMAIL_PATTERN
      SIGNATURE_TYPES = %w[signature initial].freeze

      # Validate and normalize a payload accepted by {#create} without sending
      # a request. Useful for preflighting multi-step workflows before they
      # create any remote resources.
      #
      # @param payload [Hash]
      # @option payload [String] :full_name             required
      # @option payload [String] :email                 optional, validated when present
      # @option payload [String] :whatsapp_phone_number optional
      # @option payload [String] :phone                 alias for :whatsapp_phone_number
      # @option payload [String] :government_id         CPF/CNPJ; required for DigitalCertificate signers
      # @return [Hash] normalized request body
      # @raise [ValidationError] when the payload is malformed
      # @example Preflight a signer without making an API request
      #   body = client.signers.validate_create!(
      #     full_name: 'Example Signer', email: 'signer@example.com'
      #   )
      #   # => { "full_name" => "Example Signer", "email" => "signer@example.com" }
      def validate_create!(payload)
        signer_payload(payload, require_full_name: true)
      end

      # Create a signer in the workspace.
      #
      # @param payload [Hash]
      # @option payload [String] :full_name             required
      # @option payload [String] :email                 optional, validated when present
      # @option payload [String] :whatsapp_phone_number optional
      # @option payload [String] :phone                 alias for :whatsapp_phone_number
      # @option payload [String] :government_id         CPF/CNPJ; required for DigitalCertificate signers
      # @param account_id_override [String, nil]
      # @return [Hash] signer object (envelope `data` unwrapped)
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see POST /accounts/{account_id}/signers
      # @example Create a signer
      #   signer = client.signers.create(full_name: 'Example Signer', email: 'signer@example.com')
      #
      #   # Request body the SDK sends (nil/omitted optional fields are stripped):
      #   #   {
      #   #     "full_name": "Example Signer",
      #   #     "email": "signer@example.com"
      #   #   }
      #
      #   # => {
      #   #   "resource"              => "signer",
      #   #   "id"                    => "signer-id",
      #   #   "full_name"             => "Example Signer",
      #   #   "email"                 => "signer@example.com",
      #   #   "whatsapp_phone_number" => nil,
      #   #   "has_accepted_terms"    => false
      #   # }
      def create(payload, account_id_override = nil)
        body   = validate_create!(payload)
        acc_id = account_id(account_id_override)

        @logger.info('Creating signer')

        call('Failed to create signer') do
          http_post("accounts/#{acc_id}/signers", body)
        end
      end

      # Fetch a signer by ID.
      #
      # @param signer_id           [String]
      # @param account_id_override [String, nil]
      # @return [Hash] signer object (envelope `data` unwrapped)
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see GET /accounts/{account_id}/signers/{signer_id}
      # @example Fetch a signer by ID
      #   signer = client.signers.get('signer-id')
      #
      #   # => {
      #   #   "resource"              => "signer",
      #   #   "id"                    => "signer-id",
      #   #   "full_name"             => "Example Signer",
      #   #   "email"                 => "signer@example.com",
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
      # @param params [Hash] query parameters (`search`, `page`, `per_page`)
      # @param account_id_override [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [...], meta: { ... } }`
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see GET /accounts/{account_id}/signers
      # @example List signers, page 1, 3 per page
      #   result = client.signers.list(page: 1, per_page: 3)
      #
      #   # => {
      #   #   data: [
      #   #     {
      #   #       "id"                    => "signer-id",
      #   #       "full_name"             => "Example Signer",
      #   #       "email"                 => "signer@example.com",
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

      # Partially update a signer. Omitted fields are left unchanged. Updating
      # `email` or `whatsapp_phone_number` is rejected while that channel is
      # verified on an in-flight document; changing an unverified channel rotates
      # its access and verification codes.
      #
      # @param signer_id           [String]
      # @param payload             [Hash]
      # @option payload [String] :full_name
      # @option payload [String] :email
      # @option payload [String] :whatsapp_phone_number E.164; normalized on save
      # @option payload [String] :phone alias for `:whatsapp_phone_number`
      # @option payload [String] :government_id CPF (digits) or CNPJ (may be alphanumeric); normalized on save
      # @param account_id_override [String, nil]
      # @return [Hash] updated signer object (envelope `data` unwrapped)
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see PUT /accounts/{account_id}/signers/{signer_id}
      # @example Update a signer's full name and government ID
      #   signer = client.signers.update('signer-id', full_name: 'Updated Signer',
      #                                                government_id: '00000000000')
      #
      #   # Request body the SDK sends (omitted fields are not nulled):
      #   #   { "full_name": "Updated Signer", "government_id": "00000000000" }
      #
      #   # => {
      #   #   "resource"              => "signer",
      #   #   "id"                    => "signer-id",
      #   #   "full_name"             => "Updated Signer",
      #   #   "email"                 => "signer@example.com",
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
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see DELETE /accounts/{account_id}/signers/{signer_id}
      # @example Delete a signer
      #   client.signers.delete('signer-id')
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
      # `nil` when no returned signer matches. API errors still propagate.
      #
      # @param email               [String]
      # @param account_id_override [String, nil]
      # @return [Hash, nil] the matching signer object, or nil when none matches
      # @example Find a signer by email
      #   signer = client.signers.find_by_email('signer@example.com')
      #
      #   # Internally pages through GET /accounts/{account_id}/signers?search=...&per-page=50
      #   # and returns the single matching signer Hash (case-insensitive on email):
      #   # => {
      #   #   "id"                    => "signer-id",
      #   #   "full_name"             => "Example Signer",
      #   #   "email"                 => "signer@example.com",
      #   #   "whatsapp_phone_number" => nil,
      #   #   "has_accepted_terms"    => false
      #   # }
      #   #
      #   # => nil # when no returned signer matches
      def find_by_email(email, account_id_override = nil)
        assert_email!(email)
        target = email.downcase
        page   = 1

        loop do
          result = list({ search: email, page: page, per_page: 50 }, account_id_override)
          match  = result[:data].find { |signer| signer['email'].to_s.downcase == target }
          return match if match

          meta = result[:meta]
          break unless meta && meta[:last_page] && page < meta[:last_page]

          page += 1
        end
        nil
      end

      # Fetch the authenticated signer's own profile (signer-access-code auth).
      #
      # @param signer_access_code [String]
      # @return [Hash] signer object plus self-only fields (envelope `data` unwrapped)
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see GET /signers/self
      # @example Fetch the signer's own profile
      #   me = client.signers.self_data(signer_access_code: 'signer-access-code')
      #
      #   # => {
      #   #   "resource"              => "signer",
      #   #   "id"                    => "signer-id",
      #   #   "full_name"             => "Signer Name",
      #   #   "email"                 => "signer@example.com",
      #   #   "whatsapp_phone_number" => "+15555550100",
      #   #   "has_accepted_terms"    => false,
      #   #   "has_signature"         => false, # self-only field
      #   #   "has_initial"           => false, # self-only field
      #   #   "is_signature_reusable" => false  # self-only field
      #   # }
      def self_data(signer_access_code:)
        code = require_signer_access_code(signer_access_code)

        call('Failed to fetch signer self') do
          http_get('signers/self', { signer_access_code: code }, workspace_auth: false)
        end
      end

      # Read the signer's biometric verification state. Only an absent or Expired
      # session can start again. InReview permits signing while account review
      # holds certification; Declined or Abandoned needs a new document and assignment.
      #
      # @param signer_access_code [String]
      # @return [Hash] can_start, status, url, expires_at and completed_at (nullable except can_start)
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on a missing or invalid access code
      # @see GET /signers/identity-verification
      # @example Read state with signer-only authentication
      #   client.signers.identity_verification(signer_access_code: 'signer-access-code')
      #   # GET /signers/identity-verification?signer-access-code=signer-access-code (no body)
      #   # => { 'can_start' => false, 'status' => 'Pending',
      #   #      'url' => 'https://verify.assinafy.com.br/c/session-id#t=token-placeholder',
      #   #      'expires_at' => '2026-10-16T13:00:00Z', 'completed_at' => nil }
      #   # The URL is a bearer link: open it intact, including its fragment; never log or cache it.
      def identity_verification(signer_access_code:)
        code = require_signer_access_code(signer_access_code)

        call('Failed to fetch signer identity verification') do
          http_get('signers/identity-verification', { signer_access_code: code }, workspace_auth: false)
        end
      end

      # Record explicit biometric-processing consent and open the hosted verification
      # session. Restart is allowed only after Expired; it incurs no additional fee.
      #
      # @param consent [Boolean] must be true, supplied explicitly by the signer
      # @param signer_access_code [String]
      # @return [Hash] id, hosted capture url and nullable expires_at
      # @raise [Assinafy::ApiError] on failure; 400 when a session already exists and is not Expired
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on missing consent or an invalid access code
      # @see POST /signers/identity-verification
      # @example Start with signer-only authentication after collecting consent
      #   client.signers.start_identity_verification(consent: true, signer_access_code: 'signer-access-code')
      #   # POST /signers/identity-verification?signer-access-code=signer-access-code
      #   # Body: { 'consent' => true }
      #   # => { 'id' => 'verification-id',
      #   #      'url' => 'https://verify.assinafy.com.br/c/session-id#t=token-placeholder',
      #   #      'expires_at' => '2026-10-16T13:00:00Z' }
      #   # Redirect to url unchanged, including its fragment; never log or cache the bearer link.
      def start_identity_verification(consent:, signer_access_code:)
        raise ValidationError.new('Biometric processing requires explicit consent: true') unless consent == true

        code = require_signer_access_code(signer_access_code)

        call('Failed to start signer identity verification') do
          http_post('signers/identity-verification', body_params(consent: consent),
                    { signer_access_code: code }, workspace_auth: false)
        end
      end

      # Accept the platform's terms of use as the signer.
      #
      # The `signer-access-code` is sent as the documented query parameter (the
      # `signerAccessCode` security scheme is `in: query`), consistent with every
      # other signer-authenticated endpoint. This operation has no request body.
      #
      # @param signer_access_code [String]
      # @return [Hash] full_name, email and has_accepted_terms
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see PUT /signers/accept-terms
      # @example Accept the terms of use
      #   result = client.signers.accept_terms(signer_access_code: 'signer-access-code')
      #
      #   # Request: PUT /signers/accept-terms?signer-access-code=signer-access-code
      #   # Body: none
      #
      #   # => { "full_name" => "Example Signer", "email" => "signer@example.com",
      #   #      "has_accepted_terms" => true }
      def accept_terms(signer_access_code:)
        code = require_signer_access_code(signer_access_code)

        call('Failed to accept signer terms') do
          http_put('signers/accept-terms', nil, { signer_access_code: code }, workspace_auth: false)
        end
      end

      # Verify the signer's Email or Whatsapp one-time code.
      #
      # @param verification_code  [String]
      # @param signer_access_code [String]
      # @return [Array, nil] empty Array; nil for older no-data responses
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see POST /verify
      # @example Verify the signer's email with a one-time code
      #   result = client.signers.verify_email(
      #     verification_code:  '123456',
      #     signer_access_code: 'signer-access-code'
      #   )
      #
      #   # Request: POST /verify?signer-access-code=signer-access-code
      #   # Body: { "verification-code": "123456" }
      #
      #   # Response: { "status": 200, "data": [], "message": "Code verified successfully" }
      #   # => []
      def verify_email(verification_code:, signer_access_code:)
        verification = require_string(verification_code, 'Verification code')
        code         = require_signer_access_code(signer_access_code)

        call('Failed to verify signer email') do
          http_post(
            'verify',
            body_params(verification_code: verification),
            { signer_access_code: code },
            workspace_auth: false
          )
        end
      end

      # Confirm the contact used by the assignment and optionally accept terms. Certificate signers
      # must do both before opening GET /sign. Existing additional payload fields are passed through.
      #
      # @param document_id [String]
      # @param payload [Hash] email, whatsapp_phone_number and has_accepted_terms
      # @param signer_access_code [String]
      # @return [Array] empty Array on success
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see PUT /documents/{documentId}/signers/confirm-data
      # @example Confirm contact and terms using only the signer access code
      #   client.signers.confirm_data('document-id',
      #     { email: 'signer@example.com', has_accepted_terms: true }, signer_access_code: 'access-code')
      #   # PUT /documents/document-id/signers/confirm-data?signer-access-code=access-code
      #   # Body: { 'email' => 'signer@example.com', 'has_accepted_terms' => true }
      #   # => []
      def confirm_data(document_id, payload, signer_access_code:)
        doc_id = require_id(document_id, 'Document ID')
        body   = body_params(require_payload(payload))
        code   = require_signer_access_code(signer_access_code)
        require_string(body['full_name'], 'Full name') if body.key?('full_name')
        Utils.require_email(body['email']) if body.key?('email')
        require_string(body['government_id'], 'Government ID') if body.key?('government_id')
        require_string(body['whatsapp_phone_number'], 'WhatsApp number') if body.key?('whatsapp_phone_number')
        require_boolean(body['has_accepted_terms'], 'has_accepted_terms') if body.key?('has_accepted_terms')

        call('Failed to confirm signer data') do
          http_put("documents/#{doc_id}/signers/confirm-data", body,
                   { signer_access_code: code }, workspace_auth: false)
        end
      end

      # Upload the signer's signature image. The request body is raw image bytes.
      #
      # @param content            [String] raw image bytes
      # @param signer_access_code [String]
      # @param type               [String] `signature` or `initial`
      # @param content_type       [String] must be `image/png`
      # @param reuse              [Boolean, nil] when true, marks the signature as
      #   reusable for future documents (documented `reuse` query flag)
      # @return [Array, nil] empty Array; nil for older no-data responses
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see POST /signature
      # @example Upload a PNG signature image
      #   bytes  = File.binread('signature.png')
      #   client.signers.upload_signature(
      #     bytes,
      #     signer_access_code: 'signer-access-code',
      #     type:               'signature',
      #     content_type:       'image/png'
      #   )
      #
      #   # The SDK sends the RAW image bytes as the body, with
      #   # Content-Type: image/png and ?signer-access-code=...&type=signature query params.
      #
      #   # => []
      def upload_signature(content, signer_access_code:, type: 'signature', content_type: 'image/png', reuse: nil)
        unless content.is_a?(String) && !content.empty?
          raise ValidationError.new('Signature content must be a non-empty String')
        end

        unless content_type == 'image/png'
          raise ValidationError.new('Signature content type must be image/png')
        end

        require_boolean(reuse, 'reuse') unless reuse.nil?
        sig_type = signature_type(type)
        code     = require_signer_access_code(signer_access_code)

        call('Failed to upload signer signature') do
          @connection.post('signature') do |request|
            prepare_request(
              request,
              { signer_access_code: code, type: sig_type, reuse: reuse },
              workspace_auth: false
            )
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
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @raise [Assinafy::ValidationError] on invalid required input
      # @see GET /signature/{type}
      # @example Download and save the signer's signature image
      #   png = client.signers.download_signature(
      #     signer_access_code: 'signer-access-code',
      #     type:               'signature'
      #   )
      #
      #   # The SDK returns the raw response body as binary bytes (Content-Type: image/png):
      #   # => "\x89PNG\r\n\x1A\n..." # ASCII-8BIT String
      #   File.binwrite('signature.png', png)
      def download_signature(signer_access_code:, type: 'signature')
        sig_type = signature_type(type)
        code     = require_signer_access_code(signer_access_code)

        call_binary('Failed to download signer signature') do
          http_get("signature/#{sig_type}", { signer_access_code: code }, workspace_auth: false)
        end
      end

      # Read the signing workspace's brand using the signer's access code.
      #
      # @param signer_access_code [String]
      # @return [Hash] account_name, primary_color, secondary_color and nullable logo URL
      # @raise [Assinafy::ValidationError] on an invalid access code
      # @raise [Assinafy::ApiError] on an unsuccessful API response
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @see GET /sign/theme
      # @example Read branding (no body, no workspace credentials)
      #   client.signers.theme(signer_access_code: 'access-code')
      #   # GET /sign/theme?signer-access-code=access-code
      #   # => { 'account_name' => 'Example Workspace', 'primary_color' => 'aabbcc',
      #   #      'secondary_color' => 'ffffff', 'logo' => 'https://api.assinafy.com.br/v1/sign/logo' }
      def theme(signer_access_code:)
        code = require_signer_access_code(signer_access_code)

        call('Failed to read signing theme') do
          http_get('sign/theme', { signer_access_code: code }, workspace_auth: false)
        end
      end

      # Download the signing workspace's logo with signer-only authentication.
      #
      # @param signer_access_code [String]
      # @return [String] binary image bytes
      # @raise [Assinafy::ValidationError] on an invalid access code
      # @raise [Assinafy::ApiError] on an unsuccessful API response, including 404 without a logo
      # @raise [Assinafy::NetworkError] on transport or TLS failure
      # @see GET /sign/logo
      # @example Download branding (no request body)
      #   client.signers.download_logo(signer_access_code: 'access-code')
      #   # GET /sign/logo?signer-access-code=access-code
      #   # => "PNG image bytes" # binary String
      def download_logo(signer_access_code:)
        code = require_signer_access_code(signer_access_code)

        call_binary('Failed to download signing logo') do
          http_get('sign/logo', { signer_access_code: code }, workspace_auth: false)
        end
      end

      private

      def assert_email!(email)
        Utils.require_email(email)
      end

      def signer_payload(payload, require_full_name:)
        raw = require_payload(payload, 'Signer payload')
        p   = raw.transform_keys(&:to_s)

        full_name = signer_full_name(p, require_full_name)

        email = p['email']
        assert_email!(email) unless email.nil?

        phone = signer_phone(p)

        body = body_params(
          full_name:             full_name,
          email:                 email,
          whatsapp_phone_number: phone
        )
        government_id = signer_government_id(p)
        body['government_id'] = government_id unless government_id.nil?
        body
      end

      def signer_full_name(payload, required)
        full_name = payload['full_name'].nil? ? payload['name'] : payload['full_name']
        return full_name if !required && full_name.nil?
        return full_name if full_name.is_a?(String) && !full_name.strip.empty?

        raise ValidationError.new('full_name must be a non-empty String')
      end

      def signer_phone(payload)
        phone = payload['whatsapp_phone_number'].nil? ? payload['phone'] : payload['whatsapp_phone_number']
        return phone if phone.nil? || phone.is_a?(String)

        raise ValidationError.new('whatsapp_phone_number must be a String')
      end

      def signer_government_id(payload)
        government_id = payload['government_id']
        return government_id if government_id.nil? || government_id.is_a?(String)

        raise ValidationError.new('government_id must be a String')
      end

      def signature_type(type)
        value = require_id(type, 'Signature type').to_s
        return value if SIGNATURE_TYPES.include?(value)

        raise ValidationError.new('Signature type must be signature or initial', { type: type })
      end
    end
  end
end
