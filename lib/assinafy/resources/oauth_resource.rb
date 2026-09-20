# frozen_string_literal: true

module Assinafy
  module Resources
    # OAuth 2.1 token lifecycle and OpenID Connect userinfo.
    #
    # This is the server-side half of the authorization-code flow; the browser
    # half (PKCE pair, authorization URL) lives on {Assinafy::OAuth}. Use it
    # when an application acts *in a user's workspace with that user's
    # permission*, as opposed to `api_key:`/`token:`, which authenticate the
    # workspace or the user directly.
    #
    # Three behaviours set these routes apart from the rest of the API, and the
    # SDK handles each of them here:
    #
    # 1. **No envelope.** `/oauth/token`, `/oauth/revoke` and `/oauth/userinfo`
    #    answer with flat JSON (RFC 6749 §5.1/§5.2, OIDC Core §5.3.2), never
    #    `{status, data, message}`. These methods return the body as-is.
    # 2. **No workspace credentials.** `/oauth/token` and `/oauth/revoke` are
    #    unauthenticated routes that identify the client through `client_id` in
    #    the body, so the SDK strips `X-Api-Key`/`Authorization` from them.
    # 3. **OAuth-shaped errors.** A failure raises {Assinafy::OAuthError}, which
    #    carries `error` and `error_description` separately.
    #
    # An OAuth access token never reaches billing, account lifecycle, credential
    # management or admin surfaces, whatever scopes it holds. A request missing
    # a scope answers `403` with `WWW-Authenticate: Bearer
    # error="insufficient_scope"` naming it; the SDK puts that header in
    # {Assinafy::Error#context} under `:www_authenticate`.
    #
    # @example End-to-end: exchange a callback code, then act as the user
    #   tokens = Assinafy::Client.new.oauth.exchange_code(
    #     code:          params.fetch('code'),
    #     client_id:     ENV.fetch('ASSINAFY_CLIENT_ID'),
    #     code_verifier: session.delete(:assinafy_code_verifier),
    #     redirect_uri:  'https://app.example.com/oauth/callback'
    #   )
    #
    #   user_client = Assinafy::Client.new(
    #     token:      tokens.fetch('access_token'),
    #     account_id: ENV.fetch('ASSINAFY_ACCOUNT_ID')
    #   )
    #   user_client.documents.list
    #
    # @see Assinafy::OAuth
    # @see https://api.assinafy.com.br/v1/docs
    class OAuthResource < BaseResource
      # Grant types the authorization server advertises.
      GRANT_TYPES = %w[authorization_code refresh_token].freeze

      # Accepted `token_type_hint` values on {#revoke}.
      TOKEN_TYPE_HINTS = %w[access_token refresh_token].freeze

      # Path of the RFC 9728 protected-resource metadata document. Leading
      # slash on purpose: it sits at the host root, outside the `/v1` prefix
      # that `base_url` carries.
      PROTECTED_RESOURCE_METADATA_PATH = '/.well-known/oauth-protected-resource'

      # Exchange an authorization code for tokens (RFC 6749 §4.1.3 + PKCE).
      #
      # Call this on your OAuth callback, after checking that the returned
      # `state` matches the one you stored. `code_verifier` must be the exact
      # value whose challenge was sent to
      # {Assinafy::OAuth.authorization_url} — the SDK validates its grammar
      # locally, because the server reports a malformed verifier as
      # `invalid_grant`, indistinguishable from an expired code.
      #
      # @param code          [String] the `code` query parameter from the callback
      # @param client_id     [String] the registered client identifier
      # @param code_verifier [String] the PKCE verifier stored before redirecting
      # @param redirect_uri  [String, nil] must match the one sent to `/authorize`
      # @param client_secret [String, nil] confidential clients only; public
      #   clients authenticate with PKCE and are never issued a secret
      # @param resource      [String, nil] RFC 8707 resource indicator; when sent
      #   it must match the value sent to `/authorize`, or the server answers
      #   `invalid_target`
      # @return [Hash{String=>Object}] the flat token response
      # @raise [Assinafy::OAuthError] on `invalid_grant`, `invalid_client`,
      #   `invalid_target`, or `unsupported_grant_type`
      # @raise [Assinafy::ValidationError] when the verifier breaks RFC 7636's grammar
      #
      # @see POST /oauth/token
      #
      # @example Request and response
      #   client.oauth.exchange_code(
      #     code:          'authorization-code-from-callback',
      #     client_id:     'client-id',
      #     code_verifier: verifier,
      #     redirect_uri:  'https://app.example.com/oauth/callback'
      #   )
      #
      #   # Request body sent by the SDK (no X-Api-Key/Authorization header):
      #   #   {
      #   #     "grant_type":    "authorization_code",
      #   #     "client_id":     "client-id",
      #   #     "code":          "authorization-code-from-callback",
      #   #     "code_verifier": "<43-128 unreserved characters>",
      #   #     "redirect_uri":  "https://app.example.com/oauth/callback"
      #   #   }
      #   #
      #   # Response (flat, NOT enveloped):
      #   # {
      #   #   'access_token'  => 'access-token-placeholder',
      #   #   'token_type'    => 'Bearer',
      #   #   'expires_in'    => 3600,
      #   #   'refresh_token' => 'refresh-token-placeholder', # only with offline_access
      #   #   'scope'         => 'documents:read documents:write',
      #   #   'id_token'      => 'signed-jwt'                 # only with openid
      #   # }
      def exchange_code(code:, client_id:, code_verifier:, redirect_uri: nil,
                        client_secret: nil, resource: nil)
        token(
          grant_type:    'authorization_code',
          client_id:     client_id,
          code:          require_string(code, 'Authorization code'),
          code_verifier: Assinafy::OAuth.validate_code_verifier!(code_verifier),
          redirect_uri:  redirect_uri,
          client_secret: client_secret,
          resource:      resource
        )
      end

      # Exchange a refresh token for a fresh access token (RFC 6749 §6).
      #
      # A refresh token only exists when `offline_access` was both requested and
      # consented. Without one, send the user through the authorization flow
      # again once the access token expires.
      #
      # @param refresh_token [String] issued alongside a previous access token
      # @param client_id     [String] the registered client identifier
      # @param client_secret [String, nil] confidential clients only
      # @param resource      [String, nil] RFC 8707 resource indicator
      # @return [Hash{String=>Object}] the flat token response
      # @raise [Assinafy::OAuthError] `invalid_grant` when the refresh token is
      #   unknown, revoked, or its authorization no longer includes `offline_access`
      #
      # @see POST /oauth/token
      #
      # @example Request and response
      #   client.oauth.refresh(refresh_token: stored_refresh_token, client_id: 'client-id')
      #
      #   # Request body sent by the SDK:
      #   #   { "grant_type": "refresh_token", "client_id": "client-id",
      #   #     "refresh_token": "refresh-token-placeholder" }
      #   #
      #   # Response (flat, NOT enveloped):
      #   # {
      #   #   'access_token'  => 'new-access-token',
      #   #   'token_type'    => 'Bearer',
      #   #   'expires_in'    => 3600,
      #   #   'refresh_token' => 'new-refresh-token',
      #   #   'scope'         => 'documents:read'
      #   # }
      def refresh(refresh_token:, client_id:, client_secret: nil, resource: nil)
        token(
          grant_type:    'refresh_token',
          client_id:     client_id,
          refresh_token: require_string(refresh_token, 'Refresh token'),
          client_secret: client_secret,
          resource:      resource
        )
      end

      # Call the token endpoint directly.
      #
      # {#exchange_code} and {#refresh} cover both supported grants; reach for
      # this only to send a parameter they do not model.
      #
      # @param grant_type [String] `"authorization_code"` or `"refresh_token"`
      # @param client_id  [String] the registered client identifier
      # @param params     [Hash] additional body parameters; nil values are dropped
      # @return [Hash{String=>Object}] the flat token response
      # @raise [Assinafy::OAuthError] on any non-2xx response
      # @raise [Assinafy::ValidationError] on an unsupported `grant_type`
      #
      # @see POST /oauth/token
      def token(grant_type:, client_id:, **params)
        grant = require_string(grant_type, 'Grant type')
        unless GRANT_TYPES.include?(grant)
          raise ValidationError.new("Grant type must be one of: #{GRANT_TYPES.join(', ')}", { grant_type: grant_type })
        end

        body = body_params(params.merge(grant_type: grant, client_id: require_string(client_id, 'Client ID')))

        @logger.info("Requesting OAuth token (#{grant})")
        call('Failed to exchange OAuth token') do
          http_post('oauth/token', body, {}, workspace_auth: false)
        end
      end

      # Revoke an access or refresh token (RFC 7009).
      #
      # Revoking a refresh token also invalidates the access tokens issued from
      # it. Every token outcome answers `200` — including a token that is
      # unknown, already revoked, or malformed — so the endpoint cannot be used
      # to probe whether a token exists. Only failed client authentication
      # raises.
      #
      # @param token           [String] the access or refresh token to revoke
      # @param client_id       [String] the registered client identifier
      # @param token_type_hint [String, nil] `"access_token"` or `"refresh_token"`
      # @param client_secret   [String, nil] confidential clients only
      # @return [nil] the endpoint returns no body
      # @raise [Assinafy::OAuthError] `invalid_client` (401) only
      #
      # @see POST /oauth/revoke
      #
      # @example Revoke on disconnect
      #   client.oauth.revoke(
      #     token:           stored_refresh_token,
      #     client_id:       'client-id',
      #     token_type_hint: 'refresh_token'
      #   )
      #
      #   # Request body sent by the SDK (no X-Api-Key/Authorization header):
      #   #   { "token": "refresh-token-placeholder", "client_id": "client-id",
      #   #     "token_type_hint": "refresh_token" }
      #   #
      #   # Response: HTTP 200, empty body
      #   # => nil
      def revoke(token:, client_id:, token_type_hint: nil, client_secret: nil)
        if !token_type_hint.nil? && !TOKEN_TYPE_HINTS.include?(token_type_hint.to_s)
          raise ValidationError.new(
            "Token type hint must be one of: #{TOKEN_TYPE_HINTS.join(', ')}",
            { token_type_hint: token_type_hint }
          )
        end

        body = body_params(
          token:           require_string(token, 'Token'),
          client_id:       require_string(client_id, 'Client ID'),
          token_type_hint: token_type_hint,
          client_secret:   client_secret
        )

        @logger.info('Revoking OAuth token')
        call_void('Failed to revoke OAuth token') do
          http_post('oauth/revoke', body, {}, workspace_auth: false)
        end
      end

      # Fetch OpenID Connect claims about the user who authorized the token.
      #
      # Requires the `openid` scope; `name` additionally requires `profile` and
      # `email`/`email_verified` require `email`. Per OIDC Core §5.3.2 the
      # response is a flat claims object, never this API's envelope.
      #
      # Authenticate the client with the OAuth access token (`token:` on
      # {Assinafy::Client}).
      #
      # @return [Hash{String=>Object}] the claims
      # @raise [Assinafy::OAuthError] `401` when the token is missing or invalid,
      #   `403` when a scope is missing (the `WWW-Authenticate` header naming it
      #   is in {Assinafy::Error#context} under `:www_authenticate`)
      #
      # @see GET /oauth/userinfo
      #
      # @example Request and response
      #   Assinafy::Client.new(token: access_token).oauth.userinfo
      #
      #   # Request: GET /oauth/userinfo
      #   # Header:  Authorization: Bearer <access_token>
      #   #
      #   # Response (flat, NOT enveloped):
      #   # {
      #   #   'sub'            => 'd6zqpbyog2v3xvxerwn8la94',
      #   #   'name'           => 'Example User',     # requires the profile scope
      #   #   'email'          => 'user@example.com', # requires the email scope
      #   #   'email_verified' => true
      #   # }
      def userinfo
        call('Failed to fetch OAuth userinfo') do
          http_get('oauth/userinfo')
        end
      end

      # Fetch this API's RFC 9728 protected-resource metadata.
      #
      # Names the authorization server(s) that can issue tokens for this API and
      # the scopes it accepts, so an integration discovers them rather than
      # hardcoding them. `scopes_supported` deliberately omits `offline_access`:
      # asking for a refresh token is a client concern, not something the
      # resource is protected by.
      #
      # Served from the host root, outside the `/v1` prefix, and without
      # credentials.
      #
      # @return [Hash{String=>Object}] the bare metadata object
      #
      # @see GET /.well-known/oauth-protected-resource
      #
      # @example Discover the authorization server
      #   metadata = client.oauth.protected_resource_metadata
      #
      #   # Response (bare metadata, NOT enveloped):
      #   # {
      #   #   'resource' => 'https://api.assinafy.com.br',
      #   #   'authorization_servers' => ['https://auth.assinafy.com.br'],
      #   #   'scopes_supported' => [
      #   #     'documents:read', 'documents:write', 'templates:read',
      #   #     'templates:write', 'account:read', 'openid', 'profile', 'email'
      #   #   ],
      #   #   'bearer_methods_supported' => ['header']
      #   # }
      #
      #   metadata.fetch('authorization_servers').first
      #   # => "https://auth.assinafy.com.br"
      def protected_resource_metadata
        call('Failed to fetch protected resource metadata') do
          http_get(PROTECTED_RESOURCE_METADATA_PATH, {}, workspace_auth: false)
        end
      end

      # Fetch the authorization server's RFC 8414 metadata.
      #
      # This is the document to start an integration from: it publishes the
      # authorization, token, revocation, userinfo and JWKS endpoints, the
      # supported scopes and grants, and the PKCE methods. It lives on the
      # authorization server host — not this API — so the SDK sends it without
      # credentials.
      #
      # @param url [String] override for a non-default authorization server;
      #   pass `"#{protected_resource_metadata['authorization_servers'].first}" \
      #   "/.well-known/oauth-authorization-server"` to follow discovery strictly
      # @return [Hash{String=>Object}] the bare metadata object
      #
      # @example Discover endpoints instead of hardcoding them
      #   metadata = client.oauth.authorization_server_metadata
      #
      #   # Response (bare metadata, NOT enveloped):
      #   # {
      #   #   'issuer' => 'https://auth.assinafy.com.br',
      #   #   'authorization_endpoint' => 'https://auth.assinafy.com.br/oauth/authorize',
      #   #   'token_endpoint' => 'https://api.assinafy.com.br/v1/oauth/token',
      #   #   'revocation_endpoint' => 'https://api.assinafy.com.br/v1/oauth/revoke',
      #   #   'userinfo_endpoint' => 'https://api.assinafy.com.br/v1/oauth/userinfo',
      #   #   'jwks_uri' => 'https://auth.assinafy.com.br/.well-known/jwks.json',
      #   #   'scopes_supported' => ['documents:read', '...', 'offline_access'],
      #   #   'response_types_supported' => ['code'],
      #   #   'grant_types_supported' => ['authorization_code', 'refresh_token'],
      #   #   'code_challenge_methods_supported' => ['S256'],
      #   #   'token_endpoint_auth_methods_supported' => ['client_secret_post', 'none'],
      #   #   'authorization_response_iss_parameter_supported' => true,
      #   #   'client_id_metadata_document_supported' => true
      #   # }
      def authorization_server_metadata(url = Assinafy::OAuth::AUTHORIZATION_SERVER_METADATA_URL)
        absolute = require_string(url, 'Authorization server metadata URL')

        call('Failed to fetch authorization server metadata') do
          http_get(absolute, {}, workspace_auth: false)
        end
      end

      private

      # OAuth routes report failures as RFC 6749 error objects rather than this
      # API's envelope, so they raise {OAuthError} (an {ApiError}, so existing
      # `rescue Assinafy::ApiError` handlers keep working). The
      # `WWW-Authenticate` challenge is carried along because on a 403 it names
      # the scope that was missing.
      def check_status!(response, _label)
        return if (200..299).cover?(response.status)

        error = OAuthError.from_response(response.status, response.body)
        error.context[:www_authenticate] = response.headers&.[]('www-authenticate')
        raise error
      end
    end
  end
end
