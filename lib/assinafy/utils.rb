# frozen_string_literal: true

module Assinafy
  module Utils
    class << self
      def handle_assinafy_response(body)
        return body unless body.is_a?(Hash)
        return body unless body.key?('status') && body.key?('data')

        status = body['status'].to_i
        if status >= 200 && status < 300
          body['data']
        else
          raise ApiError.from_response(status, body)
        end
      end

      def clean_params(hash)
        return {} if hash.nil?

        hash.each_with_object({}) do |(key, value), result|
          result[key] = value unless value.nil?
        end
      end

      def query_params(hash)
        normalize_keys(clean_params(hash), query_key_map)
      end

      def body_params(hash)
        normalize_keys(clean_params(hash), body_key_map)
      end

      private

      def normalize_keys(hash, key_map)
        hash.each_with_object({}) do |(key, value), result|
          result[normalize_key(key, key_map)] = normalize_value(value, key_map)
        end
      end

      def normalize_value(value, key_map)
        case value
        when Hash
          normalize_keys(value, key_map)
        when Array
          value.map { |item| item.is_a?(Hash) ? normalize_keys(item, key_map) : item }
        else
          value
        end
      end

      def normalize_key(key, key_map)
        raw = key.to_s
        key_map.fetch(raw, raw)
      end

      def query_key_map
        {
          'access_token' => 'access-token',
          'per_page' => 'per-page',
          'signer_access_code' => 'signer-access-code'
        }
      end

      def body_key_map
        {
          'signer_access_code' => 'signer-access-code',
          'verification_code' => 'verification-code'
        }
      end
    end
  end
end
