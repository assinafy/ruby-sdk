# frozen_string_literal: true

module Assinafy
  module Resources
    class BaseResource
      def initialize(connection, default_account_id = nil, logger = nil)
        @connection         = connection
        @default_account_id = default_account_id
        @logger             = logger || NullLogger.new
      end

      protected

      def account_id(explicit = nil)
        id = explicit || @default_account_id
        unless id
          raise ValidationError.new(
            'Account ID is required. Provide it as a parameter or set a default in the client.'
          )
        end
        id
      end

      def require_id(value, name)
        if value.nil? || value.to_s.strip.empty?
          raise ValidationError.new("#{name} is required")
        end
        value
      end

      def require_payload(payload, name = 'Payload')
        unless payload.is_a?(Hash)
          raise ValidationError.new("#{name} must be a Hash")
        end

        payload
      end

      def require_array(value, name)
        unless value.is_a?(Array) && !value.empty?
          raise ValidationError.new("#{name} must be a non-empty Array")
        end

        value
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

      def call(label, &block)
        response = yield
        check_status!(response, label)
        Utils.handle_assinafy_response(response.body)
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        raise NetworkError.new("#{label}: #{e.message}")
      rescue Assinafy::Error
        raise
      rescue => e
        raise Assinafy::Error.new("#{label}: #{e.message}")
      end

      def call_optional(label, &block)
        call(label, &block)
      rescue ApiError => e
        return nil if e.status_code == 404
        raise
      end

      def call_void(label, &block)
        response = yield
        check_status!(response, label)
        nil
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        raise NetworkError.new("#{label}: #{e.message}")
      rescue Assinafy::Error
        raise
      rescue => e
        raise Assinafy::Error.new("#{label}: #{e.message}")
      end

      def call_binary(label, &block)
        response = yield
        check_status!(response, label)
        (response.body || '').b
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        raise NetworkError.new("#{label}: #{e.message}")
      rescue Assinafy::Error
        raise
      rescue => e
        raise Assinafy::Error.new("#{label}: #{e.message}")
      end

      def call_list(label, &block)
        response = yield
        check_status!(response, label)

        body = Utils.handle_assinafy_response(response.body)
        data = extract_list_data(body)
        meta = parse_pagination_meta(response.headers)

        result = { data: data }
        result[:meta] = meta if meta
        result
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        raise NetworkError.new("#{label}: #{e.message}")
      rescue Assinafy::Error
        raise
      rescue => e
        raise Assinafy::Error.new("#{label}: #{e.message}")
      end

      private

      def check_status!(response, label)
        return if response.status >= 200 && response.status < 300

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

        current  = to_int(headers['x-pagination-current-page'])
        per_page = to_int(headers['x-pagination-per-page'])
        total    = to_int(headers['x-pagination-total-count'])
        last     = to_int(headers['x-pagination-page-count'])

        return nil if [current, per_page, total, last].all?(&:nil?)

        meta = {}
        meta[:current_page] = current  if current
        meta[:per_page]     = per_page if per_page
        meta[:total]        = total    if total
        meta[:last_page]    = last     if last
        meta
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
