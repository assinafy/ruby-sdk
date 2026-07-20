# frozen_string_literal: true

module Assinafy
  module Resources
    # Shared plumbing for every resource: a Faraday connection, an optional
    # default account ID, parameter normalisation, response-envelope handling,
    # pagination header parsing, and a single `request`/`call` pipeline that
    # wraps Faraday and Assinafy errors into the SDK's own error hierarchy.
    class BaseResource
      PAGINATION_HEADERS = {
        current_page: 'x-pagination-current-page',
        per_page:     'x-pagination-per-page',
        total:        'x-pagination-total-count',
        last_page:    'x-pagination-page-count'
      }.freeze

      # @param connection         [Faraday::Connection]
      # @param default_account_id [String, nil] used by `account_id` when no override is passed
      # @param logger             [Logger, nil]
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

      # Ensure a required scalar argument is present (not nil/blank).
      # `require_id` is kept as an intention-revealing alias for path IDs.
      def require_present(value, name)
        return value unless value.nil? || value.to_s.strip.empty?

        raise ValidationError.new("#{name} is required")
      end

      def require_id(value, name)
        require_present(value, name)
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

      # Normalise an upload source into `[buffer, file_name]`. Shared by every
      # multipart upload endpoint (document upload, template create, account
      # logo). Accepts a path String, or a Hash with `:file_path` (path) **or**
      # `:buffer` + `:file_name` (raw bytes).
      #
      # @param source [String, Hash]
      # @return [Array(String, String)] `[buffer, file_name]`
      # @raise [ValidationError] on an unusable source
      def read_source(source)
        case source
        when String
          [File.binread(source), File.basename(source)]
        when Hash
          if source[:buffer]
            raise ValidationError.new('file_name is required when uploading a buffer') unless source[:file_name]

            [source[:buffer], source[:file_name]]
          elsif source[:file_path]
            [File.binread(source[:file_path]), source[:file_name] || File.basename(source[:file_path])]
          else
            raise ValidationError.new('Invalid upload source: provide :file_path or :buffer')
          end
        else
          raise ValidationError.new('Invalid upload source: provide a path String or a Hash with :file_path/:buffer')
        end
      end

      # Wrap raw bytes in a Faraday::FilePart for a multipart request body.
      #
      # @param buffer       [String] raw file bytes
      # @param file_name    [String]
      # @param content_type [String] MIME type (defaults to sniffing the extension)
      # @return [Faraday::FilePart]
      def file_part(buffer, file_name, content_type = nil)
        Faraday::FilePart.new(StringIO.new(buffer), content_type || mime_type_for(file_name), file_name)
      end

      def mime_type_for(file_name)
        case File.extname(file_name.to_s).downcase
        when '.pdf'         then 'application/pdf'
        when '.png'         then 'image/png'
        when '.jpg', '.jpeg' then 'image/jpeg'
        when '.gif'         then 'image/gif'
        when '.webp'        then 'image/webp'
        when '.svg'         then 'image/svg+xml'
        else 'application/octet-stream'
        end
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

      def http_patch(path, body = nil, params = {})
        @connection.patch(path) do |request|
          request.params.update(query_params(params))
          request.body = body unless body.nil?
        end
      end

      def http_delete(path, params = {}, body: nil)
        @connection.delete(path) do |request|
          request.params.update(query_params(params))
          request.body = body unless body.nil?
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
        raise NetworkError.new("#{label}: #{e.message}", { cause: e.class.name })
      rescue Assinafy::Error
        raise
      rescue StandardError => e
        # Preserve the original class for debugging; Ruby keeps the original
        # exception accessible via #cause since we re-raise inside the rescue.
        raise Assinafy::Error.new("#{label}: #{e.message}", { cause: e.class.name })
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
