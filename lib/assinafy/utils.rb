# frozen_string_literal: true

module Assinafy
  # Small, stateless helpers shared across resources. Intentionally private
  # by convention — callers should reach for these via the resource methods,
  # not directly.
  module Utils
    class << self
      # Unwrap an Assinafy "envelope" response — a Hash with `status` and `data`
      # keys. Returns `data` on a 2xx envelope, raises {ApiError} otherwise.
      # Pass-through for any non-envelope body.
      #
      # @param body [Hash, Object]
      # @return [Object]
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

      # Drop nil values (but keep `false`).
      #
      # @param hash [Hash, nil]
      # @return [Hash]
      def clean_params(hash)
        return {} if hash.nil?

        hash.each_with_object({}) do |(key, value), result|
          result[key] = value unless value.nil?
        end
      end

      # Build a query-string Hash, translating the Ruby-friendly snake_case
      # aliases in {query_key_map} to the hyphenated forms documented in the
      # Assinafy API (e.g. `per_page` → `per-page`).
      #
      # @param hash [Hash, nil]
      # @return [Hash{String=>Object}]
      def query_params(hash)
        normalize_keys(clean_params(hash), query_key_map)
      end

      # Build a body Hash, translating documented hyphenated body keys
      # (`signer-access-code`, `verification-code`) while passing everything
      # else through as-is.
      #
      # @param hash [Hash, nil]
      # @return [Hash{String=>Object}]
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
          'access_token'       => 'access-token',
          'per_page'           => 'per-page',
          'signer_access_code' => 'signer-access-code'
        }
      end

      def body_key_map
        {
          'signer_access_code' => 'signer-access-code',
          'verification_code'  => 'verification-code'
        }
      end
    end
  end
end
