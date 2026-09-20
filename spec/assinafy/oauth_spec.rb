# frozen_string_literal: true

RSpec.describe Assinafy::OAuth do
  describe '.generate_code_verifier' do
    it 'defaults to the maximum length RFC 7636 allows' do
      expect(described_class.generate_code_verifier.length).to eq(128)
    end

    it 'honours an explicit length within the RFC bounds' do
      expect(described_class.generate_code_verifier(43).length).to eq(43)
    end

    it 'emits only unreserved characters' do
      100.times do
        verifier = described_class.generate_code_verifier(43)
        expect(verifier).to match(described_class::CODE_VERIFIER_PATTERN)
      end
    end

    it 'does not repeat itself' do
      verifiers = Array.new(50) { described_class.generate_code_verifier }

      expect(verifiers.uniq.length).to eq(50)
    end

    it 'rejects a length below the RFC minimum' do
      expect { described_class.generate_code_verifier(42) }
        .to raise_error(Assinafy::ValidationError, /between 43 and 128/)
    end

    it 'rejects a length above the RFC maximum' do
      expect { described_class.generate_code_verifier(129) }
        .to raise_error(Assinafy::ValidationError, /between 43 and 128/)
    end

    it 'rejects a non-Integer length' do
      expect { described_class.generate_code_verifier('64') }
        .to raise_error(Assinafy::ValidationError)
    end
  end

  describe '.code_challenge' do
    # RFC 7636 Appendix B publishes this verifier/challenge pair; matching it
    # proves the S256 transform, not just that some digest was taken.
    it 'matches the RFC 7636 Appendix B test vector' do
      expect(described_class.code_challenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'))
        .to eq('E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM')
    end

    it 'emits unpadded base64url' do
      challenge = described_class.code_challenge(described_class.generate_code_verifier)

      expect(challenge).to match(/\A[A-Za-z0-9\-_]{43}\z/)
    end

    it 'round-trips every generated verifier' do
      expect { described_class.code_challenge(described_class.generate_code_verifier) }
        .not_to raise_error
    end

    it 'rejects a verifier shorter than 43 characters' do
      expect { described_class.code_challenge('a' * 42) }
        .to raise_error(Assinafy::ValidationError, /43-128 characters/)
    end

    it 'rejects a verifier longer than 128 characters' do
      expect { described_class.code_challenge('a' * 129) }
        .to raise_error(Assinafy::ValidationError, /43-128 characters/)
    end

    it 'rejects characters outside the unreserved set' do
      expect { described_class.code_challenge("#{'a' * 42}+") }
        .to raise_error(Assinafy::ValidationError, /A-Za-z0-9/)
    end

    it 'rejects a non-String verifier' do
      expect { described_class.code_challenge(nil) }
        .to raise_error(Assinafy::ValidationError)
    end
  end

  describe '.generate_state' do
    it 'returns a URL-safe value' do
      expect(described_class.generate_state).to match(/\A[A-Za-z0-9\-_]+\z/)
    end

    it 'does not repeat itself' do
      states = Array.new(50) { described_class.generate_state }

      expect(states.uniq.length).to eq(50)
    end
  end

  describe '.normalize_scope' do
    it 'joins an Array with spaces' do
      expect(described_class.normalize_scope(%w[documents:read openid]))
        .to eq('documents:read openid')
    end

    it 'passes a String through, trimmed' do
      expect(described_class.normalize_scope('  documents:read  ')).to eq('documents:read')
    end

    it 'returns nil for nil' do
      expect(described_class.normalize_scope(nil)).to be_nil
    end

    it 'returns nil for a blank String' do
      expect(described_class.normalize_scope('   ')).to be_nil
    end

    it 'rejects an unsupported type' do
      expect { described_class.normalize_scope(:documents) }
        .to raise_error(Assinafy::ValidationError, /String or an Array/)
    end
  end

  describe '.authorization_url' do
    let(:verifier) { 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk' }
    let(:url) do
      described_class.authorization_url(
        client_id:     'client-id',
        redirect_uri:  'https://app.example.com/oauth/callback',
        code_verifier: verifier,
        scope:         %w[documents:read offline_access],
        state:         'state-token'
      )
    end
    let(:params) { URI.decode_www_form(URI.parse(url).query).to_h }

    it 'targets the published authorization endpoint' do
      expect(url).to start_with("#{described_class::AUTHORIZATION_ENDPOINT}?")
    end

    it 'requests the authorization-code response type' do
      expect(params['response_type']).to eq('code')
    end

    it 'carries the client identifier and redirect URI' do
      expect(params).to include(
        'client_id'    => 'client-id',
        'redirect_uri' => 'https://app.example.com/oauth/callback'
      )
    end

    it 'space-delimits the requested scopes' do
      expect(params['scope']).to eq('documents:read offline_access')
    end

    it 'derives the S256 challenge from the verifier' do
      expect(params).to include(
        'code_challenge'        => 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
        'code_challenge_method' => 'S256'
      )
    end

    it 'never leaks the verifier into the URL' do
      expect(url).not_to include(verifier)
    end

    it 'carries the CSRF state' do
      expect(params['state']).to eq('state-token')
    end

    it 'omits parameters that were not supplied' do
      minimal = described_class.authorization_url(
        client_id: 'c', redirect_uri: 'https://example.com/cb', code_verifier: verifier
      )

      expect(URI.decode_www_form(URI.parse(minimal).query).to_h.keys)
        .to contain_exactly('response_type', 'client_id', 'redirect_uri',
                            'code_challenge', 'code_challenge_method')
    end

    it 'accepts a pre-computed challenge instead of a verifier' do
      built = described_class.authorization_url(
        client_id:      'c',
        redirect_uri:   'https://example.com/cb',
        code_challenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM'
      )

      expect(URI.decode_www_form(URI.parse(built).query).to_h['code_challenge'])
        .to eq('E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM')
    end

    it 'includes an RFC 8707 resource indicator when given' do
      built = described_class.authorization_url(
        client_id: 'c', redirect_uri: 'https://example.com/cb',
        code_verifier: verifier, resource: 'https://api.assinafy.com.br'
      )

      expect(URI.decode_www_form(URI.parse(built).query).to_h['resource'])
        .to eq('https://api.assinafy.com.br')
    end

    it 'merges extra query parameters' do
      built = described_class.authorization_url(
        client_id: 'c', redirect_uri: 'https://example.com/cb',
        code_verifier: verifier, prompt: 'consent'
      )

      expect(URI.decode_www_form(URI.parse(built).query).to_h['prompt']).to eq('consent')
    end

    it 'percent-encodes the redirect URI' do
      expect(url).to include('redirect_uri=https%3A%2F%2Fapp.example.com%2Foauth%2Fcallback')
    end

    it 'rejects a request with neither verifier nor challenge' do
      expect do
        described_class.authorization_url(client_id: 'c', redirect_uri: 'https://example.com/cb')
      end.to raise_error(Assinafy::ValidationError, /exactly one/)
    end

    it 'rejects a request with both verifier and challenge' do
      expect do
        described_class.authorization_url(
          client_id: 'c', redirect_uri: 'https://example.com/cb',
          code_verifier: verifier, code_challenge: 'challenge'
        )
      end.to raise_error(Assinafy::ValidationError, /exactly one/)
    end

    it 'rejects a blank client_id' do
      expect do
        described_class.authorization_url(
          client_id: '  ', redirect_uri: 'https://example.com/cb', code_verifier: verifier
        )
      end.to raise_error(Assinafy::ValidationError, /client_id is required/)
    end

    it 'rejects a missing redirect_uri' do
      expect do
        described_class.authorization_url(
          client_id: 'c', redirect_uri: nil, code_verifier: verifier
        )
      end.to raise_error(Assinafy::ValidationError, /redirect_uri is required/)
    end

    it 'rejects a malformed verifier before building a URL' do
      expect do
        described_class.authorization_url(
          client_id: 'c', redirect_uri: 'https://example.com/cb', code_verifier: 'too-short'
        )
      end.to raise_error(Assinafy::ValidationError, /43-128 characters/)
    end
  end

  describe 'published constants' do
    it 'points at the authorization server the API advertises' do
      expect(described_class::AUTHORIZATION_SERVER).to eq('https://auth.assinafy.com.br')
    end

    it 'derives the RFC 8414 metadata URL from the authorization server' do
      expect(described_class::AUTHORIZATION_SERVER_METADATA_URL)
        .to eq('https://auth.assinafy.com.br/.well-known/oauth-authorization-server')
    end

    it 'only offers the S256 challenge method the server supports' do
      expect(described_class::CODE_CHALLENGE_METHOD).to eq('S256')
    end

    it 'lists the scopes the authorization server advertises' do
      expect(described_class::SCOPES).to eq(
        %w[documents:read documents:write templates:read templates:write
           account:read openid profile email offline_access]
      )
    end
  end
end
