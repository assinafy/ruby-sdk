# frozen_string_literal: true

module Assinafy
  module Resources
    class BaseResource
      PAGINATION_HEADERS = {
        current_page: 'x-pagination-current-page',
        per_page:     'x-pagination-per-page',
        total:        'x-pagination-total-count',
        last_page:    'x-pagination-page-count'
      }.freeze

      def initialize(connection, default_account_id = nil, logger = nil)
        @connection         = connection
        @default_account_id = default_account_id
        @logger             = logger || NullLogger.new
      end

      protected

      def account_id(explicit = nil)
        id = explicit || @default_account_id
        return id if id

        raise ValidationError.new(
          'Account ID is required. Provide it as a parameter or set a default in the client.'
        )
      end

      def require_id(value, name)
        return value unless value.nil? || value.to_s.strip.empty?

        raise ValidationError.new("#{name} is required")
      end

      def require_payload(payload, name = 'Payload')
        raise ValidationError.new("#{name} must be a Hash") unless payload.is_a?(Hash)

        payload
      end

      def require_array(value, name)
        return value if value.is_a?(Array) && !value.empty?

        raise ValidationError.new("#{name} must be a non-empty Array")
      end

      def query_params(params)
        Utils.query_params(params)
      end

      def body_params(params)
        Utils.body_params(params)
      end

      def http_get(path, params = {})
        @connection.get(path, query_params(params))
      end

      def http_post(path, body = nil, params = {})
        @connection.post(path) do |request|
          request.params.update(query_params(params))
          request.body = body unless body.nil?
        end
      end

      def http_put(path, body = nil, params = {})
        @connection.put(path) do |request|
          request.params.update(query_params(params))
          request.body = body unless body.nil?
        end
      end

      def http_delete(path, params = {})
        @connection.delete(path) do |request|
          request.params.update(query_params(params))
        end
      end

      def call(label)
        Utils.handle_assinafy_response(request(label) { yield }.body)
      end

      def call_optional(label)
        call(label) { yield }
      rescue ApiError => e
        raise unless e.status_code == 404

        nil
      end

      def call_void(label)
        request(label) { yield }
        nil
      end

      def call_binary(label)
        (request(label) { yield }.body || '').b
      end

      def call_list(label)
        response = request(label) { yield }
        body     = Utils.handle_assinafy_response(response.body)
        result   = { data: extract_list_data(body) }
        meta     = parse_pagination_meta(response.headers)
        result[:meta] = meta if meta
        result
      end

      private

      def request(label)
        response = yield
        check_status!(response, label)
        response
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        raise NetworkError.new("#{label}: #{e.message}")
      rescue Assinafy::Error
        raise
      rescue StandardError => e
        raise Assinafy::Error.new("#{label}: #{e.message}")
      end

      def check_status!(response, _label)
        return if (200..299).cover?(response.status)

        raise ApiError.from_response(response.status, response.body)
      end

      def extract_list_data(body)
        case body
        when Array then body
        when Hash  then body['data'] || []
        else            []
        end
      end

      def parse_pagination_meta(headers)
        return nil unless headers

        meta = PAGINATION_HEADERS.each_with_object({}) do |(key, header), acc|
          value = to_int(headers[header])
          acc[key] = value if value
        end
        meta.empty? ? nil : meta
      end

      def to_int(value)
        return nil if value.nil?

        Integer(value)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
