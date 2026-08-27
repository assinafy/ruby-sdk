# frozen_string_literal: true

module Assinafy
  module Resources
    # Shared plumbing for every resource: a Faraday connection, an optional
    # default account ID, parameter normalisation, response-envelope handling,
    # pagination header parsing, and a single `request`/`call` pipeline that
    # wraps Faraday and Assinafy errors into the SDK's own error hierarchy.
    class BaseResource
      PATH_SEGMENT = /\A[A-Za-z0-9._~-]+\z/
      AUTH_HEADERS = %w[X-Api-Key Authorization].freeze
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
        @connection = connection
        @connection.headers['User-Agent'] = USER_AGENT
        @default_account_id = default_account_id.is_a?(String) ? default_account_id.dup.freeze : default_account_id
        @logger             = logger || NullLogger.new
      end

      protected

      def account_id(explicit = nil)
        require_id(explicit.nil? ? @default_account_id : explicit, 'Account ID')
      end

      # Ensure a required scalar argument is present (not nil/blank).
      # `require_id` is kept as an intention-revealing alias for path IDs.
      def require_present(value, name)
        return value unless value.nil? || value.to_s.strip.empty?

        raise ValidationError.new("#{name} is required")
      end

      def require_id(value, name)
        id = require_string(value, name)

        return id if PATH_SEGMENT.match?(id) && id != '.' && id != '..'

        raise ValidationError.new("#{name} contains invalid characters")
      end

      def require_string(value, name)
        string = require_present(value, name)
        return string if string.is_a?(String)

        raise ValidationError.new("#{name} must be a String")
      end

      def require_boolean(value, name)
        return value if [true, false].include?(value)

        raise ValidationError.new("#{name} must be true or false")
      end

      def require_payload(payload, name = 'Payload')
        raise ValidationError.new("#{name} must be a Hash") unless payload.is_a?(Hash)

        payload
      end

      def require_array(value, name)
        return value if value.is_a?(Array) && !value.empty?

        raise ValidationError.new("#{name} must be a non-empty Array")
      end

      def require_signer_access_code(value)
        require_string(value, 'Signer access code')
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
      # @param max_bytes [Integer, nil] read at most one byte beyond this limit
      # @return [Array(String, String)] `[buffer, file_name]`
      # @raise [ValidationError] on an unusable source
      def read_source(source, max_bytes: nil)
        buffer, file_name =
          case source
          when String
            [read_file(source, max_bytes), File.basename(source)]
          when Hash
            if source.key?(:buffer)
              raise ValidationError.new('file_name is required when uploading a buffer') unless source[:file_name]

              [source[:buffer], source[:file_name]]
            elsif source[:file_path]
              [read_file(source[:file_path], max_bytes), source[:file_name] || File.basename(source[:file_path])]
            else
              raise ValidationError.new('Invalid upload source: provide :file_path or :buffer')
            end
          else
            raise ValidationError.new('Invalid upload source: provide a path String or a Hash with :file_path/:buffer')
          end

        validate_upload_source!(buffer, file_name)
        [buffer, file_name]
      rescue SystemCallError, ArgumentError, TypeError => e
        raise ValidationError.new("Unable to read upload source: #{e.message}", { cause: e.class.name })
      end

      def read_file(path, max_bytes)
        return File.binread(path) unless max_bytes

        File.binread(path, max_bytes + 1)
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

      def validate_pdf_source!(buffer, file_name, max_bytes: nil)
        unless file_name.downcase.end_with?('.pdf')
          raise ValidationError.new('Only PDF files are supported', { file_name: file_name })
        end

        if max_bytes && buffer.bytesize > max_bytes
          raise ValidationError.new(
            'File size exceeds maximum allowed (25MB)',
            { file_size: buffer.bytesize, max_size: max_bytes }
          )
        end

        return if buffer.byteslice(0, 1024).to_s.include?('%PDF-')

        raise ValidationError.new('File content is not a PDF', { file_name: file_name })
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

      def http_get(path, params = {}, workspace_auth: true)
        @connection.get(path) do |request|
          prepare_request(request, params, workspace_auth: workspace_auth)
        end
      end

      def http_post(path, body = nil, params = {}, workspace_auth: true)
        @connection.post(path) do |request|
          prepare_request(request, params, workspace_auth: workspace_auth)
          request.body = body unless body.nil?
        end
      end

      def http_put(path, body = nil, params = {}, workspace_auth: true)
        @connection.put(path) do |request|
          prepare_request(request, params, workspace_auth: workspace_auth)
          request.body = body unless body.nil?
        end
      end

      def http_patch(path, body = nil, params = {}, workspace_auth: true)
        @connection.patch(path) do |request|
          prepare_request(request, params, workspace_auth: workspace_auth)
          request.body = body unless body.nil?
        end
      end

      def http_delete(path, params = {}, body: nil, workspace_auth: true)
        @connection.delete(path) do |request|
          prepare_request(request, params, workspace_auth: workspace_auth)
          request.body = body unless body.nil?
        end
      end

      def prepare_request(request, params, workspace_auth:)
        request.params.update(query_params(params))
        AUTH_HEADERS.each { |header| request.headers.delete(header) } unless workspace_auth
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
        call(label) { yield }
        nil
      end

      def call_binary(label)
        response = request(label) { yield }
        body = response.body
        body = Utils.handle_assinafy_response(body) if body.is_a?(Hash)
        content_type = response.headers&.[]('content-type').to_s.downcase

        if body.is_a?(String) && !body.empty? && !textual_content_type?(content_type)
          return body.b
        end

        raise unexpected_response(label, 'a non-empty binary body', response, body)
      end

      def call_array(label)
        response = request(label) { yield }
        body = Utils.handle_assinafy_response(response.body)
        return body if body.is_a?(Array)

        raise unexpected_response(label, 'an Array data payload', response, body)
      end

      def call_list(label)
        response = request(label) { yield }
        body     = Utils.handle_assinafy_response(response.body)
        # @type var result: Assinafy::list_result
        result   = { data: extract_list_data(body, label, response) }
        meta     = parse_pagination_meta(response.headers)
        result[:meta] = meta if meta
        result
      end

      private

      def request(label)
        @connection.headers['User-Agent'] = USER_AGENT
        response = yield
        check_status!(response, label)
        response
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError => e
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

      def extract_list_data(body, label, response)
        data = body.is_a?(Hash) && body.key?('data') ? body['data'] : body
        return data if data.is_a?(Array)

        raise unexpected_response(label, 'an Array list payload', response, data)
      end

      def validate_upload_source!(buffer, file_name)
        raise ValidationError.new('File buffer must be a String') unless buffer.is_a?(String)
        raise ValidationError.new('File buffer is empty') if buffer.empty?

        unless file_name.is_a?(String) && !file_name.strip.empty?
          raise ValidationError.new('File name must be a non-empty String')
        end

        return unless file_name.match?(%r{[\x00-\x1f\x7f\\/]})

        raise ValidationError.new('File name contains invalid characters', { file_name: file_name })
      end

      def textual_content_type?(content_type)
        content_type.start_with?('text/') || content_type.match?(%r{\Aapplication/(?:[^;]+\+)?json\b})
      end

      def unexpected_response(label, expected, response, body)
        Assinafy::Error.new(
          "#{label}: expected #{expected}",
          {
            status_code:  response.status,
            content_type: response.headers&.[]('content-type'),
            body_class:   body.class.name,
            body_bytes:   body.is_a?(String) ? body.bytesize : nil
          }
        )
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
