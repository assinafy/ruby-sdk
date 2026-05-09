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
  end

  describe '.clean_params' do
    it 'drops nil values and keeps everything else' do
      result = described_class.clean_params({ a: 1, b: nil, c: 'x', d: false })
      expect(result).to eq({ a: 1, c: 'x', d: false })
    end

    it 'returns an empty hash when all values are nil' do
      expect(described_class.clean_params({ a: nil, b: nil })).to eq({})
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
  end
end
