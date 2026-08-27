# frozen_string_literal: true

RSpec.describe Assinafy::Resources::SignerResource do
  let(:base_url)   { 'https://api.assinafy.com.br/v1' }
  let(:connection) do
    build_test_connection(base_url).tap do |configured_connection|
      configured_connection.headers['Authorization'] = 'Bearer workspace-token'
    end
  end
  let(:resource) { described_class.new(connection, 'test-account') }

  def workspace_auth_absent?(request)
    !request.headers.key?('X-Api-Key') && !request.headers.key?('Authorization')
  end

  describe '#update' do
    it 'raises when signer ID is empty' do
      expect { resource.update('', { full_name: 'Test' }) }.to raise_error(Assinafy::ValidationError)
    end

    it 'sends the documented government_id field' do
      stub_request(:put, "#{base_url}/accounts/test-account/signers/signer-1")
        .with(body: hash_including('government_id' => '00000000000'))
        .to_return(api_envelope({ 'id' => 'signer-1' }))

      resource.update('signer-1', government_id: '00000000000')

      expect(
        a_request(:put, "#{base_url}/accounts/test-account/signers/signer-1")
          .with(body: hash_including('government_id' => '00000000000'))
      ).to have_been_made
    end

    it 'omits a nil government_id because the update field is not nullable' do
      stub_request(:put, "#{base_url}/accounts/test-account/signers/signer-1")
        .with(body: {})
        .to_return(api_envelope({ 'id' => 'signer-1' }))

      resource.update('signer-1', government_id: nil)

      expect(
        a_request(:put, "#{base_url}/accounts/test-account/signers/signer-1").with(body: {})
      ).to have_been_made
    end
  end

  describe '#delete' do
    it 'raises when signer ID is empty' do
      expect { resource.delete('') }.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '#create' do
    it 'raises when no account ID is available' do
      r = described_class.new(connection)
      expect do
        r.create(full_name: 'Test', email: 'test@example.com')
      end.to raise_error(Assinafy::ValidationError)
    end

    it 'rejects an invalid email' do
      expect do
        resource.create(full_name: 'Test', email: 'not-an-email')
      end.to raise_error(Assinafy::ValidationError)
    end

    it 'uses custom account_id when provided' do
      stub_request(:post, "#{base_url}/accounts/custom-account/signers")
        .to_return(api_envelope({ 'id' => '123' }))

      resource.create({ full_name: 'Test', email: 'test@example.com' }, 'custom-account')

      expect(a_request(:post, "#{base_url}/accounts/custom-account/signers")).to have_been_made
    end

    it 'uses default account_id when custom not provided' do
      stub_request(:post, "#{base_url}/accounts/test-account/signers")
        .to_return(api_envelope({ 'id' => '123' }))

      resource.create(full_name: 'Test', email: 'test@example.com')

      expect(a_request(:post, "#{base_url}/accounts/test-account/signers")).to have_been_made
    end

    it 'maps phone to whatsapp_phone_number in the request body' do
      stub_request(:post, "#{base_url}/accounts/test-account/signers")
        .to_return(api_envelope({ 'id' => '123' }))

      resource.create(full_name: 'John', email: 'john@example.com', phone: '+5548999990000')

      expect(
        a_request(:post, "#{base_url}/accounts/test-account/signers")
          .with(body: hash_including(
            'full_name'             => 'John',
            'email'                 => 'john@example.com',
            'whatsapp_phone_number' => '+5548999990000'
          ))
      ).to have_been_made
    end
  end

  describe '#validate_create!' do
    it 'normalizes a valid create payload without sending a request' do
      result = resource.validate_create!(
        full_name: 'Example Signer', email: 'signer@example.test', phone: '+15555550100'
      )

      expect(result).to eq(
        'full_name'             => 'Example Signer',
        'email'                 => 'signer@example.test',
        'whatsapp_phone_number' => '+15555550100'
      )
      expect(a_request(:any, /\A#{Regexp.escape(base_url)}/)).not_to have_been_made
    end

    it 'applies the same required-name validation as create' do
      expect { resource.validate_create!(email: 'signer@example.test') }
        .to raise_error(Assinafy::ValidationError, /full_name/)
    end

    it 'rejects non-String signer fields without sending a request' do
      malformed = [
        { full_name: false },
        { full_name: 123 },
        { full_name: 'Signer', email: false },
        { full_name: 'Signer', email: 123 },
        { full_name: 'Signer', phone: 123 }
      ]

      malformed.each do |payload|
        expect { resource.validate_create!(payload) }.to raise_error(Assinafy::ValidationError)
      end
      expect(a_request(:any, /\A#{Regexp.escape(base_url)}/)).not_to have_been_made
    end
  end

  describe '#get' do
    it 'raises when signer ID is empty' do
      expect { resource.get('') }.to raise_error(Assinafy::ValidationError)
    end

    it 'fetches a signer by ID and returns the unwrapped data' do
      stub_request(:get, "#{base_url}/accounts/test-account/signers/sig-1")
        .to_return(api_envelope({ 'id' => 'sig-1', 'full_name' => 'John' }))

      result = resource.get('sig-1')

      expect(a_request(:get, "#{base_url}/accounts/test-account/signers/sig-1")).to have_been_made
      expect(result['id']).to eq('sig-1')
    end
  end

  describe '#self_data' do
    it 'uses signer-access-code as a query parameter' do
      stub_request(:get, "#{base_url}/signers/self")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(api_envelope({ 'id' => 'signer' }))

      result = resource.self_data(signer_access_code: 'code')

      expect(
        a_request(:get, "#{base_url}/signers/self")
          .with(query: hash_including('signer-access-code' => 'code')) do |request|
            workspace_auth_absent?(request)
          end
      ).to have_been_made
      expect(result['id']).to eq('signer')
    end

    it 'rejects nil and blank signer access codes before sending a request' do
      [nil, '  '].each do |code|
        expect { resource.self_data(signer_access_code: code) }
          .to raise_error(Assinafy::ValidationError, /Signer access code/)
      end

      expect(a_request(:get, "#{base_url}/signers/self")).not_to have_been_made
    end
  end

  describe '#accept_terms' do
    it 'sends signer-access-code as the documented query parameter and handles no-data success' do
      stub_request(:put, "#{base_url}/signers/accept-terms")
        .with(query: hash_including('signer-access-code' => 'code')) { |request| request.body.to_s.empty? }
        .to_return(json_response({ 'status' => 200, 'message' => 'Terms accepted' }))

      expect(resource.accept_terms(signer_access_code: 'code')).to be_nil

      expect(
        a_request(:put, "#{base_url}/signers/accept-terms")
          .with(query: hash_including('signer-access-code' => 'code')) do |request|
            request.body.to_s.empty? && workspace_auth_absent?(request)
          end
      ).to have_been_made
    end

    it 'rejects nil and blank signer access codes before sending a request' do
      [nil, '  '].each do |code|
        expect { resource.accept_terms(signer_access_code: code) }
          .to raise_error(Assinafy::ValidationError, /Signer access code/)
      end

      expect(a_request(:put, "#{base_url}/signers/accept-terms")).not_to have_been_made
    end
  end

  describe '#verify_email' do
    it 'sends the access code and OTP in their documented locations and handles no-data success' do
      stub_request(:post, "#{base_url}/verify")
        .with(query: hash_including('signer-access-code' => 'code'), body: { 'verification-code' => '123456' })
        .to_return(json_response({ 'status' => 200, 'message' => 'Code verified successfully' }))

      expect(resource.verify_email(verification_code: '123456', signer_access_code: 'code')).to be_nil

      expect(
        a_request(:post, "#{base_url}/verify")
          .with(query: hash_including('signer-access-code' => 'code'),
                body:  { 'verification-code' => '123456' }) { |request| workspace_auth_absent?(request) }
      ).to have_been_made
    end

    it 'rejects nil and blank signer access codes before sending a request' do
      [nil, '  '].each do |code|
        expect { resource.verify_email(verification_code: '123456', signer_access_code: code) }
          .to raise_error(Assinafy::ValidationError, /Signer access code/)
      end

      expect(a_request(:post, "#{base_url}/verify")).not_to have_been_made
    end

    it 'rejects a missing, blank, or non-String verification code before sending a request' do
      [nil, ' ', 123].each do |verification_code|
        expect do
          resource.verify_email(verification_code: verification_code, signer_access_code: 'code')
        end.to raise_error(Assinafy::ValidationError, /Verification code/)
      end

      expect(a_request(:post, "#{base_url}/verify")).not_to have_been_made
    end
  end

  describe '#confirm_data' do
    it 'puts signer data with signer-access-code query parameter' do
      stub_request(:put, "#{base_url}/documents/doc/signers/confirm-data")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(api_envelope({}))

      resource.confirm_data('doc', { has_accepted_terms: true }, signer_access_code: 'code')

      expect(
        a_request(:put, "#{base_url}/documents/doc/signers/confirm-data")
          .with(
            query: hash_including('signer-access-code' => 'code'),
            body:  hash_including('has_accepted_terms' => true)
          ) { |request| workspace_auth_absent?(request) }
      ).to have_been_made
    end

    it 'rejects nil and blank signer access codes before sending a request' do
      [nil, '  '].each do |code|
        expect { resource.confirm_data('doc', {}, signer_access_code: code) }
          .to raise_error(Assinafy::ValidationError, /Signer access code/)
      end

      expect(a_request(:put, "#{base_url}/documents/doc/signers/confirm-data")).not_to have_been_made
    end
  end

  describe '#upload_signature' do
    it 'posts raw bytes with Content-Type and type + signer-access-code query params' do
      stub_request(:post, "#{base_url}/signature")
        .with(query: hash_including('signer-access-code' => 'code', 'type' => 'signature'))
        .to_return(api_envelope([]))

      result = resource.upload_signature('rawbytes', signer_access_code: 'code', content_type: 'image/png')

      expect(
        a_request(:post, "#{base_url}/signature")
          .with(
            query:   hash_including('signer-access-code' => 'code', 'type' => 'signature'),
            body:    'rawbytes',
            headers: { 'Content-Type' => 'image/png' }
          ) { |request| workspace_auth_absent?(request) }
      ).to have_been_made
      expect(result).to eq([])
    end

    it 'returns nil for the official no-data success envelope' do
      stub_request(:post, "#{base_url}/signature")
        .with(query: hash_including('signer-access-code' => 'code', 'type' => 'signature'))
        .to_return(json_response({ 'status' => 200, 'message' => 'Signature saved' }))

      expect(resource.upload_signature('rawbytes', signer_access_code: 'code')).to be_nil
    end

    it 'rejects nil and blank signer access codes before sending a request' do
      [nil, '  '].each do |code|
        expect { resource.upload_signature('rawbytes', signer_access_code: code) }
          .to raise_error(Assinafy::ValidationError, /Signer access code/)
      end

      expect(a_request(:post, "#{base_url}/signature")).not_to have_been_made
    end

    it 'rejects an empty or non-String signature body before sending a request' do
      [nil, '', []].each do |content|
        expect { resource.upload_signature(content, signer_access_code: 'code') }
          .to raise_error(Assinafy::ValidationError, /Signature content/)
      end

      expect(a_request(:post, "#{base_url}/signature")).not_to have_been_made
    end

    it 'rejects unsupported content types and non-boolean reuse values before sending a request' do
      expect do
        resource.upload_signature('rawbytes', signer_access_code: 'code', content_type: 'image/jpeg')
      end.to raise_error(Assinafy::ValidationError, %r{image/png})
      expect do
        resource.upload_signature('rawbytes', signer_access_code: 'code', reuse: 'true')
      end.to raise_error(Assinafy::ValidationError, /reuse/)

      expect(a_request(:post, "#{base_url}/signature")).not_to have_been_made
    end
  end

  describe '#download_signature' do
    it 'gets the typed signature path and returns the raw binary bytes' do
      stub_request(:get, "#{base_url}/signature/initial")
        .with(query: hash_including('signer-access-code' => 'code'))
        .to_return(status: 200, body: 'PNGBYTES', headers: { 'Content-Type' => 'image/png' })

      result = resource.download_signature(signer_access_code: 'code', type: 'initial')

      expect(
        a_request(:get, "#{base_url}/signature/initial")
          .with(query: hash_including('signer-access-code' => 'code')) do |request|
            workspace_auth_absent?(request)
          end
      ).to have_been_made
      expect(result).to eq('PNGBYTES')
      expect(result.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it 'rejects nil and blank signer access codes before sending a request' do
      [nil, '  '].each do |code|
        expect { resource.download_signature(signer_access_code: code) }
          .to raise_error(Assinafy::ValidationError, /Signer access code/)
      end

      expect(a_request(:get, %r{/signature/})).not_to have_been_made
    end
  end

  describe '#list' do
    it 'passes search via query params' do
      stub_request(:get, "#{base_url}/accounts/test-account/signers")
        .with(query: hash_including('search' => 'john@example.com'))
        .to_return(api_envelope([]))

      resource.list(search: 'john@example.com')

      expect(
        a_request(:get, "#{base_url}/accounts/test-account/signers")
          .with(query: hash_including('search' => 'john@example.com'))
      ).to have_been_made
    end

    it 'returns meta parsed from X-Pagination-* response headers' do
      stub_request(:get, "#{base_url}/accounts/test-account/signers")
        .with(query: hash_including('page' => '2'))
        .to_return(
          api_envelope([]).merge(
            headers: {
              'Content-Type'              => 'application/json',
              'x-pagination-current-page' => '2',
              'x-pagination-per-page'     => '20',
              'x-pagination-total-count'  => '45',
              'x-pagination-page-count'   => '3'
            }
          )
        )

      result = resource.list(page: 2)

      expect(result[:meta]).to eq(
        { current_page: 2, per_page: 20, total: 45, last_page: 3 }
      )
    end
  end

  describe '#find_by_email' do
    it 'returns nil when no signer matches' do
      stub_request(:get, "#{base_url}/accounts/test-account/signers")
        .with(query: hash_including('search' => 'nobody@example.com'))
        .to_return(api_envelope([]))

      expect(resource.find_by_email('nobody@example.com')).to be_nil
    end

    it 'propagates a list endpoint 404 instead of treating it as no match' do
      stub_request(:get, "#{base_url}/accounts/test-account/signers")
        .with(query: hash_including('search' => 'nobody@example.com'))
        .to_return(json_response({ 'status' => 404, 'message' => 'Account not found' }, status: 404))

      expect { resource.find_by_email('nobody@example.com') }
        .to raise_error(Assinafy::ApiError) { |error| expect(error.status_code).to eq(404) }
    end

    it 'requests per-page 50 and returns the matching signer (case-insensitive)' do
      stub_request(:get, "#{base_url}/accounts/test-account/signers")
        .with(query: hash_including('search' => 'john@example.com', 'per-page' => '50'))
        .to_return(api_envelope([{ 'id' => '1', 'full_name' => 'John', 'email' => 'JOHN@EXAMPLE.COM' }]))

      result = resource.find_by_email('john@example.com')

      expect(
        a_request(:get, "#{base_url}/accounts/test-account/signers")
          .with(query: hash_including('search' => 'john@example.com', 'per-page' => '50'))
      ).to have_been_made
      expect(result['id']).to eq('1')
    end

    it 'walks subsequent result pages' do
      first_page = api_envelope([]).merge(
        headers: {
          'Content-Type'              => 'application/json',
          'x-pagination-current-page' => '1',
          'x-pagination-page-count'   => '2'
        }
      )
      second_page = api_envelope([{ 'id' => '2', 'email' => 'JOHN@EXAMPLE.COM' }])
      stub_request(:get, "#{base_url}/accounts/test-account/signers")
        .with(query: hash_including('page' => '1')).to_return(first_page)
      stub_request(:get, "#{base_url}/accounts/test-account/signers")
        .with(query: hash_including('page' => '2')).to_return(second_page)

      expect(resource.find_by_email('john@example.com')['id']).to eq('2')
    end

    it 'stops at the requested last page even if response current-page metadata is stale' do
      stale_meta = {
        'Content-Type'              => 'application/json',
        'x-pagination-current-page' => '1',
        'x-pagination-page-count'   => '2'
      }
      stub_request(:get, "#{base_url}/accounts/test-account/signers")
        .with(query: hash_including('page' => '1')).to_return(api_envelope([]).merge(headers: stale_meta))
      stub_request(:get, "#{base_url}/accounts/test-account/signers")
        .with(query: hash_including('page' => '2')).to_return(api_envelope([]).merge(headers: stale_meta))

      expect(resource.find_by_email('john@example.com')).to be_nil
      expect(
        a_request(:get, "#{base_url}/accounts/test-account/signers").with(query: hash_including('page' => '1'))
      ).to have_been_made.once
      expect(
        a_request(:get, "#{base_url}/accounts/test-account/signers").with(query: hash_including('page' => '2'))
      ).to have_been_made.once
      expect(
        a_request(:get, "#{base_url}/accounts/test-account/signers").with(query: hash_including('page' => '3'))
      ).not_to have_been_made
    end
  end
end
