# frozen_string_literal: true

module Assinafy
  # Small, stateless helpers shared across resources. Intentionally private
  # by convention — callers should reach for these via the resource methods,
  # not directly.
  module Utils
    MAX_NORMALIZATION_DEPTH = 100

    class << self
      # Unwrap an Assinafy envelope — a Hash with a numeric `status` and an
      # optional `data` key. Returns `data` (or nil) for 2xx, raises {ApiError}
      # otherwise, and passes through non-envelope bodies.
      #
      # @param body [Hash, Object]
      # @return [Object]
      def handle_assinafy_response(body)
        return body unless body.is_a?(Hash)
        return body unless body.key?('status')

        status = Integer(body['status'], exception: false)
        return body unless status

        if status >= 200 && status < 300
          body['data'] if body.key?('data')
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
        raise ValidationError.new('Parameters must be a Hash') unless hash.is_a?(Hash)

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

      def normalize_keys(hash, key_map, seen = {}.compare_by_identity, depth = 0)
        if depth > MAX_NORMALIZATION_DEPTH || seen.key?(hash)
          raise ValidationError.new('Parameters are nested too deeply or contain a cycle')
        end

        seen[hash] = true
        hash.each_with_object({}) do |(key, value), result|
          result[normalize_key(key, key_map)] = normalize_value(value, key_map, seen, depth)
        end
      ensure
        seen.delete(hash)
      end

      def normalize_value(value, key_map, seen, depth)
        case value
        when Hash
          normalize_keys(value, key_map, seen, depth + 1)
        when Array
          normalize_array(value, key_map, seen, depth + 1)
        else
          value
        end
      end

      def normalize_array(array, key_map, seen, depth)
        if depth > MAX_NORMALIZATION_DEPTH || seen.key?(array)
          raise ValidationError.new('Parameters are nested too deeply or contain a cycle')
        end

        seen[array] = true
        array.map { |item| normalize_value(item, key_map, seen, depth) }
      ensure
        seen.delete(array)
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
