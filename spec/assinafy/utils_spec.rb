# frozen_string_literal: true

RSpec.describe Assinafy::Utils do
  describe '.handle_assinafy_response' do
    it 'returns data on a 2xx envelope' do
      result = described_class.handle_assinafy_response({ 'status' => 200, 'data' => { 'id' => '123' } })
      expect(result).to eq({ 'id' => '123' })
    end

    it 'raises ApiError on a non-2xx envelope' do
      expect do
        described_class.handle_assinafy_response({ 'status' => 400, 'message' => 'Bad', 'data' => {} })
      end.to raise_error(Assinafy::ApiError)
    end

    it 'passes through when no envelope structure is present' do
      result = described_class.handle_assinafy_response({ 'foo' => 'bar' })
      expect(result).to eq({ 'foo' => 'bar' })
    end

    it 'returns nil unchanged' do
      expect(described_class.handle_assinafy_response(nil)).to be_nil
    end

    it 'returns nil for a successful envelope without data' do
      expect(described_class.handle_assinafy_response({ 'status' => 200, 'message' => 'OK' })).to be_nil
    end

    it 'raises for an error envelope without data' do
      expect do
        described_class.handle_assinafy_response({ 'status' => 400, 'message' => 'Bad request' })
      end.to raise_error(Assinafy::ApiError, 'Bad request')
    end
  end

  describe '.clean_params' do
    it 'drops nil values and keeps everything else' do
      result = described_class.clean_params({ a: 1, b: nil, c: 'x', d: false })
      expect(result).to eq({ a: 1, c: 'x', d: false })
    end

    it 'returns an empty hash when all values are nil' do
      expect(described_class.clean_params({ a: nil, b: nil })).to eq({})
    end

    it 'rejects non-Hash parameters' do
      expect { described_class.clean_params([]) }.to raise_error(Assinafy::ValidationError)
    end
  end

  describe '.query_params' do
    it 'maps documented hyphenated query aliases without changing regular underscores' do
      expect(described_class.query_params(per_page: 20, signer_access_code: 'code',
                                          include_inactive: true)).to eq(
                                            'per-page'           => 20,
                                            'signer-access-code' => 'code',
                                            'include_inactive'   => true
                                          )
    end
  end

  describe '.body_params' do
    it 'maps only documented hyphenated body fields' do
      expect(described_class.body_params(full_name: 'John', signer_access_code: 'code')).to eq(
        'full_name'          => 'John',
        'signer-access-code' => 'code'
      )
    end

    it 'rejects cyclic input without overflowing the stack' do
      payload = {}
      payload[:self] = payload

      expect { described_class.body_params(payload) }.to raise_error(Assinafy::ValidationError, /cycle/)
    end

    it 'rejects cyclic arrays without overflowing the stack' do
      values = []
      values << values

      expect { described_class.body_params(values: values) }.to raise_error(Assinafy::ValidationError, /cycle/)
    end
  end

  describe '.require_expiration' do
    it 'accepts a zoned deadline and preserves nil' do
      expect(described_class.require_expiration('2099-12-31T23:59:00Z')).to eq('2099-12-31T23:59:00Z')
      expect(described_class.require_expiration(nil)).to be_nil
    end

    it 'rejects invalid offsets that DateTime otherwise normalizes to UTC' do
      %w[2099-12-31T23:59:00+99:99 2099-12-31T23:59:00+14:99].each do |deadline|
        expect { described_class.require_expiration(deadline) }.to raise_error(Assinafy::ValidationError)
      end
    end

    it 'rejects malformed, impossible, timezone-free and too-soon deadlines' do
      ['', 'not-a-date', '2099-02-30T12:00:00Z', '2099-12-31', '2099-12-31T12:00:00',
       (Time.now + 1800).iso8601].each do |value|
        expect { described_class.require_expiration(value) }.to raise_error(Assinafy::ValidationError)
      end
    end
  end
end
