# frozen_string_literal: true

require 'digest'
require 'securerandom'
require 'uri'

module Assinafy
  # Browser-side half of the OAuth 2.1 authorization-code flow: generating a
  # PKCE pair and building the URL the user is sent to. Everything after the
  # redirect back (code exchange, refresh, revocation, userinfo) lives on
  # {Resources::OAuthResource}.
  #
  # Assinafy's authorization server publishes `code_challenge_methods_supported:
  # ["S256"]` only, so PKCE is mandatory and `plain` is never accepted. These
  # helpers exist so an integration never hand-rolls the S256 transform.
  #
  # @example Full authorization-code flow with PKCE
  #   # 1. Before redirecting, mint and store a verifier for this user session.
  #   verifier = Assinafy::OAuth.generate_code_verifier
  #   state    = Assinafy::OAuth.generate_state
  #   session[:assinafy_code_verifier] = verifier
  #   session[:assinafy_state]         = state
  #
  #   # 2. Send the user to the authorization server.
  #   redirect_to Assinafy::OAuth.authorization_url(
  #     client_id:     ENV.fetch('ASSINAFY_CLIENT_ID'),
  #     redirect_uri:  'https://app.example.com/oauth/callback',
  #     code_verifier: verifier,
  #     scope:         %w[documents:read documents:write offline_access],
  #     state:         state
  #   )
  #   # => "https://auth.assinafy.com.br/oauth/authorize?response_type=code&client_id=...
  #   #     &redirect_uri=https%3A%2F%2Fapp.example.com%2Foauth%2Fcallback
  #   #     &scope=documents%3Aread+documents%3Awrite+offline_access&state=...
  #   #     &code_challenge=...&code_challenge_method=S256"
  #
  #   # 3. On the callback, compare `state`, then exchange the code
  #   #    (see Resources::OAuthResource#exchange_code).
  #
  # @see https://api.assinafy.com.br/v1/docs
  module OAuth
    # Authorization server that owns the browser-facing flow. Published by
    # `GET /.well-known/oauth-protected-resource` as `authorization_servers[0]`.
    AUTHORIZATION_SERVER = 'https://auth.assinafy.com.br'

    # RFC 8414 discovery document for {AUTHORIZATION_SERVER}.
    AUTHORIZATION_SERVER_METADATA_URL =
      "#{AUTHORIZATION_SERVER}/.well-known/oauth-authorization-server".freeze

    # Where the user is sent to approve the request.
    AUTHORIZATION_ENDPOINT = "#{AUTHORIZATION_SERVER}/oauth/authorize".freeze

    # The only `code_challenge_method` the server accepts.
    CODE_CHALLENGE_METHOD = 'S256'

    # Scopes the authorization server advertises. `offline_access` is a
    # request-time signal (it asks for a refresh token) rather than a
    # permission, so it never comes back in the granted `scope`.
    SCOPES = %w[
      documents:read
      documents:write
      templates:read
      templates:write
      account:read
      openid
      profile
      email
      offline_access
    ].freeze

    # RFC 7636 bounds on a `code_verifier`, enforced by the token endpoint:
    # anything outside them is rejected with `invalid_grant`.
    MIN_CODE_VERIFIER_LENGTH = 43
    MAX_CODE_VERIFIER_LENGTH = 128
    # RFC 7636 §4.1 grammar: unreserved characters only.
    CODE_VERIFIER_PATTERN = /\A[A-Za-z0-9\-._~]+\z/

    class << self
      # Generate a cryptographically random PKCE `code_verifier`.
      #
      # Store it in the user's session before redirecting; the same value must
      # be sent to {Resources::OAuthResource#exchange_code}.
      #
      # @param length [Integer] verifier length, 43..128 (default 128, the
      #   maximum entropy the grammar allows)
      # @return [String] a URL-safe verifier matching {CODE_VERIFIER_PATTERN}
      # @raise [ValidationError] when `length` is outside RFC 7636's bounds
      #
      # @example
      #   Assinafy::OAuth.generate_code_verifier.length # => 128
      #   Assinafy::OAuth.generate_code_verifier(43).length # => 43
      def generate_code_verifier(length = MAX_CODE_VERIFIER_LENGTH)
        unless length.is_a?(Integer) &&
               length.between?(MIN_CODE_VERIFIER_LENGTH, MAX_CODE_VERIFIER_LENGTH)
          raise ValidationError.new(
            "Code verifier length must be between #{MIN_CODE_VERIFIER_LENGTH} and " \
            "#{MAX_CODE_VERIFIER_LENGTH}",
            { length: length }
          )
        end

        # urlsafe_base64 emits unpadded [A-Za-z0-9_-], a subset of the
        # unreserved set, and always more characters than bytes requested.
        SecureRandom.urlsafe_base64(length)[0, length]
      end

      # Derive the `code_challenge` for a verifier: BASE64URL(SHA256(verifier)),
      # unpadded, per RFC 7636 §4.2.
      #
      # @param code_verifier [String] from {.generate_code_verifier}
      # @return [String] the S256 challenge to send to {.authorization_url}
      # @raise [ValidationError] when the verifier breaks RFC 7636's grammar
      #
      # @example The RFC 7636 Appendix B test vector
      #   Assinafy::OAuth.code_challenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk')
      #   # => "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
      def code_challenge(code_verifier)
        verifier = validate_code_verifier!(code_verifier)

        # Unpadded base64url, without the `base64` gem (no longer a default
        # gem on Ruby 3.4+; not worth a runtime dependency for one call).
        [Digest::SHA256.digest(verifier)].pack('m0').tr('+/', '-_').delete('=')
      end

      # Generate an opaque `state` value for CSRF protection.
      #
      # Store it alongside the verifier and compare it against the `state`
      # echoed back on the callback before exchanging the code.
      #
      # @return [String] 43 URL-safe characters
      #
      # @example
      #   Assinafy::OAuth.generate_state # => "kf3Yy..."
      def generate_state
        SecureRandom.urlsafe_base64(32)
      end

      # Build the authorization URL the user's browser is redirected to.
      #
      # Pass either `code_verifier` (the challenge is derived for you, the
      # common case) or a pre-computed `code_challenge`.
      #
      # @param client_id      [String]  the registered client identifier
      # @param redirect_uri   [String]  must match the URI registered for the client
      # @param code_verifier  [String, nil]  PKCE verifier; the S256 challenge is derived from it
      # @param code_challenge [String, nil]  pre-computed S256 challenge, if the verifier lives elsewhere
      # @param scope          [Array<String>, String, nil] requested scopes; include
      #   `offline_access` to be issued a refresh token
      # @param state          [String, nil] CSRF token echoed back on the callback
      # @param resource       [String, nil] RFC 8707 resource indicator; when sent
      #   here it must also be sent to the token endpoint, and must be the
      #   `resource` published by `/.well-known/oauth-protected-resource`
      # @param authorization_endpoint [String] override for a non-default server
      # @param extra_params   [Hash] additional query parameters, merged last
      # @return [String] the absolute URL to redirect to
      # @raise [ValidationError] on a missing client_id/redirect_uri, an invalid
      #   verifier, or when neither (or both) of verifier/challenge are given
      #
      # @example Minimal read-only request
      #   Assinafy::OAuth.authorization_url(
      #     client_id:     'client-id',
      #     redirect_uri:  'https://app.example.com/oauth/callback',
      #     code_verifier: verifier,
      #     scope:         'documents:read'
      #   )
      def authorization_url(client_id:, redirect_uri:, code_verifier: nil, code_challenge: nil,
                            scope: nil, state: nil, resource: nil,
                            authorization_endpoint: AUTHORIZATION_ENDPOINT, **extra_params)
        challenge = resolve_code_challenge(code_verifier, code_challenge)

        params = {
          'response_type'         => 'code',
          'client_id'             => require_value!(client_id, 'client_id'),
          'redirect_uri'          => require_value!(redirect_uri, 'redirect_uri'),
          'scope'                 => normalize_scope(scope),
          'state'                 => state,
          'resource'              => resource,
          'code_challenge'        => challenge,
          'code_challenge_method' => CODE_CHALLENGE_METHOD
        }.compact
        extra_params.each { |key, value| params[key.to_s] = value unless value.nil? }

        uri = URI.parse(authorization_endpoint)
        uri.query = URI.encode_www_form(params)
        uri.to_s
      end

      # Normalize a scope argument into the space-delimited form the
      # authorization server expects.
      #
      # @param scope [Array<String>, String, nil]
      # @return [String, nil] e.g. `"documents:read documents:write"`
      #
      # @example
      #   Assinafy::OAuth.normalize_scope(%w[documents:read openid])
      #   # => "documents:read openid"
      def normalize_scope(scope)
        case scope
        when nil    then nil
        when String then scope.strip.empty? ? nil : scope.strip
        when Array  then normalize_scope(scope.join(' '))
        else raise ValidationError.new('scope must be a String or an Array of Strings', { scope: scope })
        end
      end

      # Validate a `code_verifier` against RFC 7636's grammar and length bounds.
      #
      # The token endpoint rejects a malformed verifier with `invalid_grant`,
      # which is indistinguishable from an expired code; checking locally turns
      # that into an actionable error.
      #
      # @param code_verifier [String]
      # @return [String] the verifier, unchanged
      # @raise [ValidationError] when it is not 43-128 unreserved characters
      def validate_code_verifier!(code_verifier)
        valid = code_verifier.is_a?(String) &&
                code_verifier.length.between?(MIN_CODE_VERIFIER_LENGTH, MAX_CODE_VERIFIER_LENGTH) &&
                CODE_VERIFIER_PATTERN.match?(code_verifier)
        return code_verifier if valid

        raise ValidationError.new(
          "Code verifier must be #{MIN_CODE_VERIFIER_LENGTH}-#{MAX_CODE_VERIFIER_LENGTH} " \
          'characters from [A-Za-z0-9-._~]',
          { length: code_verifier.is_a?(String) ? code_verifier.length : nil }
        )
      end

      private

      def resolve_code_challenge(verifier, challenge)
        if verifier.nil? == challenge.nil?
          raise ValidationError.new('Provide exactly one of code_verifier or code_challenge')
        end

        challenge || code_challenge(verifier)
      end

      def require_value!(value, name)
        return value if value.is_a?(String) && !value.strip.empty?

        raise ValidationError.new("#{name} is required")
      end
    end
  end
end
