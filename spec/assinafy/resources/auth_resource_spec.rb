# frozen_string_literal: true

RSpec.describe Assinafy::Resources::AuthResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) { build_test_connection(base_url) }
  let(:resource)   { described_class.new(connection) }

  describe '#login' do
    it 'posts credentials to /login' do
      stub_request(:post, "#{base_url}/login")
        .to_return(api_envelope({ 'access_token' => 'token' }))

      result = resource.login(email: 'user@example.com', password: 'secret')

      expect(result['access_token']).to eq('token')
      expect(
        a_request(:post, "#{base_url}/login")
          .with(body: hash_including('email' => 'user@example.com', 'password' => 'secret'))
      ).to have_been_made
    end
  end

  describe '#social_login' do
    it 'posts the provider payload to /authentication/social-login' do
      stub_request(:post, "#{base_url}/authentication/social-login")
        .to_return(api_envelope({ 'access_token' => 'token' }))

      result = resource.social_login(provider: 'google', token: 'oauth-token', has_accepted_terms: true)

      expect(result['access_token']).to eq('token')
      expect(
        a_request(:post, "#{base_url}/authentication/social-login")
          .with(body: hash_including('provider' => 'google', 'token' => 'oauth-token', 'has_accepted_terms' => true))
      ).to have_been_made
    end
  end

  describe '#create_api_key' do
    it 'posts to /users/api-keys' do
      stub_request(:post, "#{base_url}/users/api-keys")
        .to_return(api_envelope({ 'api_key' => 'key' }))

      expect(resource.create_api_key(password: 'secret')['api_key']).to eq('key')
    end
  end

  describe '#get_api_key' do
    it 'gets from /users/api-keys' do
      stub_request(:get, "#{base_url}/users/api-keys")
        .to_return(api_envelope({ 'api_key' => 'masked' }))

      expect(resource.get_api_key['api_key']).to eq('masked')
      expect(a_request(:get, "#{base_url}/users/api-keys")).to have_been_made
    end

    it 'is aliased as #api_key hitting the same endpoint' do
      stub_request(:get, "#{base_url}/users/api-keys")
        .to_return(api_envelope({ 'api_key' => 'masked' }))

      expect(resource.api_key['api_key']).to eq('masked')
      expect(a_request(:get, "#{base_url}/users/api-keys")).to have_been_made
    end
  end

  describe '#delete_api_key' do
    it 'deletes /users/api-keys and returns nil' do
      stub_request(:delete, "#{base_url}/users/api-keys")
        .to_return(api_envelope({}))

      expect(resource.delete_api_key).to be_nil
      expect(a_request(:delete, "#{base_url}/users/api-keys")).to have_been_made
    end
  end

  describe '#change_password' do
    it 'puts credentials to /authentication/change-password' do
      stub_request(:put, "#{base_url}/authentication/change-password")
        .to_return(api_envelope({ 'email' => 'user@example.com' }))

      resource.change_password(email: 'user@example.com', password: 'old', new_password: 'new')

      expect(
        a_request(:put, "#{base_url}/authentication/change-password")
          .with(body: hash_including('email' => 'user@example.com', 'password' => 'old', 'new_password' => 'new'))
      ).to have_been_made
    end
  end

  describe '#reset_password' do
    it 'puts the token in the body when provided' do
      stub_request(:put, "#{base_url}/authentication/reset-password")
        .to_return(api_envelope({ 'email' => 'user@example.com' }))

      resource.reset_password(email: 'user@example.com', new_password: 'new', token: 'tok')

      expect(
        a_request(:put, "#{base_url}/authentication/reset-password")
          .with(body: hash_including('email' => 'user@example.com', 'token' => 'tok', 'new_password' => 'new'))
      ).to have_been_made
    end

    it 'omits the token from the body when nil' do
      stub_request(:put, "#{base_url}/authentication/reset-password")
        .to_return(api_envelope({ 'email' => 'user@example.com' }))

      resource.reset_password(email: 'user@example.com', new_password: 'new')

      expect(
        a_request(:put, "#{base_url}/authentication/reset-password")
          .with { |req| !JSON.parse(req.body).key?('token') }
      ).to have_been_made
    end
  end

  describe '#request_password_reset' do
    it 'puts to the password reset request endpoint' do
      stub_request(:put, "#{base_url}/authentication/request-password-reset")
        .to_return(api_envelope({ 'email' => 'user@example.com' }))

      resource.request_password_reset(email: 'user@example.com')

      expect(a_request(:put, "#{base_url}/authentication/request-password-reset")).to have_been_made
    end
  end
end
