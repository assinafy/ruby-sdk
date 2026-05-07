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

  describe '#create_api_key' do
    it 'posts to /users/api-keys' do
      stub_request(:post, "#{base_url}/users/api-keys")
        .to_return(api_envelope({ 'api_key' => 'key' }))

      expect(resource.create_api_key(password: 'secret')['api_key']).to eq('key')
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
