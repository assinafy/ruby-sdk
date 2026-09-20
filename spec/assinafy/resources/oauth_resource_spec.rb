# frozen_string_literal: true

RSpec.describe Assinafy::Resources::OAuthResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }
  let(:resource)   { described_class.new(connection) }

  # The token endpoint answers with a flat RFC 6749 §5.1 object, never this
  # API's {status, data, message} envelope.
  let(:token_response) do
    {
      'access_token'  => 'access-token-placeholder',
      'token_type'    => 'Bearer',
      'expires_in'    => 3600,
      'refresh_token' => 'refresh-token-placeholder',
      'scope'         => 'documents:read documents:write'
    }
  end

  # RFC 7636 Appendix B's published verifier, so the derived challenge is a
  # value anyone can check against the RFC rather than against this code.
  def verifier
    'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'
  end

  def unauthenticated_request
    ->(request) { !request.headers.key?('X-Api-Key') && !request.headers.key?('Authorization') }
  end

  def body_keys_of(request)
    JSON.parse(request.body).keys.sort
  end

  describe '#exchange_code' do
    it 'posts the authorization_code grant and returns the flat token body' do
      stub_request(:post, "#{base_url}/oauth/token")
        .to_return(json_response(token_response))

      result = resource.exchange_code(
        code:          'auth-code',
        client_id:     'client-id',
        code_verifier: verifier,
        redirect_uri:  'https://app.example.com/oauth/callback'
      )

      expect(result).to eq(token_response)
      expect(
        a_request(:post, "#{base_url}/oauth/token").with(
          body: {
            'grant_type'    => 'authorization_code',
            'client_id'     => 'client-id',
            'code'          => 'auth-code',
            'code_verifier' => verifier,
            'redirect_uri'  => 'https://app.example.com/oauth/callback'
          }
        )
      ).to have_been_made
    end

    it 'sends no workspace credentials' do
      stub_request(:post, "#{base_url}/oauth/token")
        .with(&unauthenticated_request)
        .to_return(json_response(token_response))

      resource.exchange_code(code: 'c', client_id: 'i', code_verifier: verifier)

      expect(a_request(:post, "#{base_url}/oauth/token")).to have_been_made
    end

    it 'omits optional parameters that were not supplied' do
      stub_request(:post, "#{base_url}/oauth/token").to_return(json_response(token_response))

      resource.exchange_code(code: 'c', client_id: 'i', code_verifier: verifier)

      sent = a_request(:post, "#{base_url}/oauth/token")
             .with { |req| body_keys_of(req) == %w[client_id code code_verifier grant_type] }

      expect(sent).to have_been_made
    end

    it 'forwards client_secret and the RFC 8707 resource indicator' do
      stub_request(:post, "#{base_url}/oauth/token").to_return(json_response(token_response))

      resource.exchange_code(
        code: 'c', client_id: 'i', code_verifier: verifier,
        client_secret: 'secret', resource: 'https://api.assinafy.com.br'
      )

      expect(
        a_request(:post, "#{base_url}/oauth/token").with(
          body: hash_including(
            'client_secret' => 'secret',
            'resource'      => 'https://api.assinafy.com.br'
          )
        )
      ).to have_been_made
    end

    # The server reports a malformed verifier as `invalid_grant`, which is
    # indistinguishable from an expired code. Catching it locally keeps the
    # failure diagnosable.
    it 'rejects a malformed code_verifier before sending anything' do
      expect do
        resource.exchange_code(code: 'c', client_id: 'i', code_verifier: 'too-short')
      end.to raise_error(Assinafy::ValidationError, /43-128 characters/)

      expect(a_request(:post, "#{base_url}/oauth/token")).not_to have_been_made
    end

    it 'rejects a blank authorization code before sending anything' do
      expect do
        resource.exchange_code(code: '  ', client_id: 'i', code_verifier: verifier)
      end.to raise_error(Assinafy::ValidationError, /Authorization code is required/)

      expect(a_request(:post, "#{base_url}/oauth/token")).not_to have_been_made
    end

    it 'raises OAuthError carrying the error code and description' do
      stub_request(:post, "#{base_url}/oauth/token").to_return(
        json_response(
          { 'error' => 'invalid_grant', 'error_description' => 'The code has expired.' },
          status: 400
        )
      )

      expect do
        resource.exchange_code(code: 'c', client_id: 'i', code_verifier: verifier)
      end.to raise_error(
        an_instance_of(Assinafy::OAuthError).and(
          having_attributes(
            status_code:       400,
            error:             'invalid_grant',
            error_description: 'The code has expired.',
            message:           'invalid_grant: The code has expired.'
          )
        )
      )
    end

    it 'raises an OAuthError that existing ApiError handlers still catch' do
      stub_request(:post, "#{base_url}/oauth/token").to_return(
        json_response({ 'error' => 'invalid_client' }, status: 401)
      )

      expect do
        resource.exchange_code(code: 'c', client_id: 'i', code_verifier: verifier)
      end.to raise_error(Assinafy::ApiError)
    end
  end

  describe '#refresh' do
    it 'posts the refresh_token grant' do
      stub_request(:post, "#{base_url}/oauth/token")
        .with(&unauthenticated_request)
        .to_return(json_response(token_response))

      expect(resource.refresh(refresh_token: 'stored-refresh', client_id: 'client-id'))
        .to eq(token_response)

      expect(
        a_request(:post, "#{base_url}/oauth/token").with(
          body: {
            'grant_type'    => 'refresh_token',
            'client_id'     => 'client-id',
            'refresh_token' => 'stored-refresh'
          }
        )
      ).to have_been_made
    end

    it 'rejects a blank refresh token before sending anything' do
      expect { resource.refresh(refresh_token: '', client_id: 'i') }
        .to raise_error(Assinafy::ValidationError, /Refresh token is required/)

      expect(a_request(:post, "#{base_url}/oauth/token")).not_to have_been_made
    end

    it 'surfaces a revoked refresh token as invalid_grant' do
      stub_request(:post, "#{base_url}/oauth/token").to_return(
        json_response(
          { 'error' => 'invalid_grant', 'error_description' => 'Refresh token revoked.' },
          status: 400
        )
      )

      expect { resource.refresh(refresh_token: 'gone', client_id: 'i') }
        .to raise_error(Assinafy::OAuthError) { |e| expect(e.error).to eq('invalid_grant') }
    end
  end

  describe '#token' do
    it 'rejects a grant type the authorization server does not support' do
      expect { resource.token(grant_type: 'password', client_id: 'i') }
        .to raise_error(Assinafy::ValidationError, /authorization_code, refresh_token/)

      expect(a_request(:post, "#{base_url}/oauth/token")).not_to have_been_made
    end

    it 'rejects a blank client_id' do
      expect { resource.token(grant_type: 'refresh_token', client_id: '  ') }
        .to raise_error(Assinafy::ValidationError, /Client ID is required/)
    end
  end

  describe '#revoke' do
    it 'posts the token without workspace credentials and returns nil' do
      stub_request(:post, "#{base_url}/oauth/revoke")
        .with(&unauthenticated_request)
        .to_return(status: 200, body: '')

      expect(
        resource.revoke(token: 'a-token', client_id: 'client-id', token_type_hint: 'refresh_token')
      ).to be_nil

      expect(
        a_request(:post, "#{base_url}/oauth/revoke").with(
          body: {
            'token'           => 'a-token',
            'client_id'       => 'client-id',
            'token_type_hint' => 'refresh_token'
          }
        )
      ).to have_been_made
    end

    # RFC 7009: an unknown or already-revoked token is indistinguishable from a
    # successful revocation, by design.
    it 'treats an unknown token as success' do
      stub_request(:post, "#{base_url}/oauth/revoke").to_return(status: 200, body: '')

      expect(resource.revoke(token: 'never-existed', client_id: 'i')).to be_nil
    end

    it 'rejects an unsupported token_type_hint before sending anything' do
      expect { resource.revoke(token: 't', client_id: 'i', token_type_hint: 'id_token') }
        .to raise_error(Assinafy::ValidationError, /access_token, refresh_token/)

      expect(a_request(:post, "#{base_url}/oauth/revoke")).not_to have_been_made
    end

    it 'omits token_type_hint when it was not supplied' do
      stub_request(:post, "#{base_url}/oauth/revoke").to_return(status: 200, body: '')

      resource.revoke(token: 't', client_id: 'i')

      sent = a_request(:post, "#{base_url}/oauth/revoke")
             .with { |req| body_keys_of(req) == %w[client_id token] }

      expect(sent).to have_been_made
    end

    it 'raises invalid_client when client authentication fails' do
      stub_request(:post, "#{base_url}/oauth/revoke").to_return(
        json_response(
          { 'error' => 'invalid_client', 'error_description' => 'Client authentication failed.' },
          status: 401
        )
      )

      expect { resource.revoke(token: 't', client_id: 'wrong') }
        .to raise_error(Assinafy::OAuthError) { |e| expect(e.error).to eq('invalid_client') }
    end
  end

  describe '#userinfo' do
    let(:claims) do
      {
        'sub'            => 'd6zqpbyog2v3xvxerwn8la94',
        'name'           => 'Example User',
        'email'          => 'user@example.com',
        'email_verified' => true
      }
    end

    it 'gets the flat claims object with workspace credentials attached' do
      stub_request(:get, "#{base_url}/oauth/userinfo")
        .with(headers: { 'X-Api-Key' => 'test-key' })
        .to_return(json_response(claims))

      expect(resource.userinfo).to eq(claims)
    end

    # A 403 names the missing scope in WWW-Authenticate; losing that header
    # turns "which scope do I re-request?" into guesswork.
    it 'carries the WWW-Authenticate challenge into the error context' do
      challenge = 'Bearer error="insufficient_scope", scope="documents:read"'
      stub_request(:get, "#{base_url}/oauth/userinfo").to_return(
        json_response(
          { 'status' => 403, 'message' => 'You are not allowed to perform this action.' },
          status:  403,
          headers: { 'WWW-Authenticate' => challenge }
        )
      )

      expect { resource.userinfo }.to raise_error(
        an_instance_of(Assinafy::OAuthError).and(
          having_attributes(status_code: 403, context: hash_including(www_authenticate: challenge))
        )
      )
    end

    # userinfo answers with this API's ordinary envelope on failure, unlike the
    # token endpoint's flat RFC 6749 object. Both must read sensibly.
    it 'reads the message from an enveloped error body' do
      stub_request(:get, "#{base_url}/oauth/userinfo").to_return(
        json_response(
          { 'status' => 401, 'message' => 'Your request was made with invalid credentials.' },
          status: 401
        )
      )

      expect { resource.userinfo }.to raise_error(
        Assinafy::OAuthError, 'Your request was made with invalid credentials.'
      )
    end
  end

  describe '#protected_resource_metadata' do
    let(:metadata) do
      {
        'resource'                 => 'https://api.assinafy.com.br',
        'authorization_servers'    => ['https://auth.assinafy.com.br'],
        'scopes_supported'         => %w[documents:read documents:write],
        'bearer_methods_supported' => ['header']
      }
    end

    # RFC 8615 puts /.well-known at the host root, so this must escape the /v1
    # prefix that base_url carries.
    it 'gets the document from the host root, outside the /v1 prefix' do
      stub_request(:get, 'https://api.assinafy.com.br/.well-known/oauth-protected-resource')
        .with(&unauthenticated_request)
        .to_return(json_response(metadata))

      expect(resource.protected_resource_metadata).to eq(metadata)
    end
  end

  describe '#authorization_server_metadata' do
    let(:metadata) do
      {
        'issuer'                           => 'https://auth.assinafy.com.br',
        'authorization_endpoint'           => 'https://auth.assinafy.com.br/oauth/authorize',
        'token_endpoint'                   => 'https://api.assinafy.com.br/v1/oauth/token',
        'code_challenge_methods_supported' => ['S256']
      }
    end

    it 'gets the RFC 8414 document from the authorization server host' do
      stub_request(:get, Assinafy::OAuth::AUTHORIZATION_SERVER_METADATA_URL)
        .to_return(json_response(metadata))

      expect(resource.authorization_server_metadata).to eq(metadata)
    end

    # The authorization server is a different host; leaking the workspace key
    # to it would hand a third party a live credential.
    it 'never sends workspace credentials to the authorization server' do
      stub_request(:get, Assinafy::OAuth::AUTHORIZATION_SERVER_METADATA_URL)
        .with(&unauthenticated_request)
        .to_return(json_response(metadata))

      resource.authorization_server_metadata

      expect(a_request(:get, Assinafy::OAuth::AUTHORIZATION_SERVER_METADATA_URL)).to have_been_made
    end

    it 'accepts a discovered override URL' do
      url = 'https://auth.example.com/.well-known/oauth-authorization-server'
      stub_request(:get, url).to_return(json_response(metadata))

      expect(resource.authorization_server_metadata(url)).to eq(metadata)
    end
  end

  describe 'client wiring' do
    it 'is exposed as Client#oauth' do
      client = Assinafy::Client.new(api_key: 'k', account_id: 'a')

      expect(client.oauth).to be_a(described_class)
    end

    it 'works on a client built without any credentials' do
      stub_request(:post, "#{base_url}/oauth/token")
        .with(&unauthenticated_request)
        .to_return(json_response(token_response))

      result = Assinafy::Client.new.oauth.exchange_code(
        code: 'c', client_id: 'i', code_verifier: verifier
      )

      expect(result['access_token']).to eq('access-token-placeholder')
    end

    it 'accepts the issued access token as a bearer credential' do
      client = Assinafy::Client.new(token: 'access-token-placeholder', account_id: 'a')

      expect(client.faraday_connection.headers['Authorization'])
        .to eq('Bearer access-token-placeholder')
    end
  end
end
