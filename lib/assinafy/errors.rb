# frozen_string_literal: true

module Assinafy
  # Base class for all errors raised by the SDK. Carries an optional context
  # Hash that may contain useful debugging details (e.g. response data, IDs).
  class Error < StandardError
    # @return [Hash] arbitrary metadata about the error
    attr_reader :context

    def initialize(message = nil, context = {})
      super(message)
      @context = context || {}
    end
  end

  # Raised when the API responds with a non-2xx status, or with a 2xx
  # response envelope whose embedded status code indicates failure.
  #
  # The Assinafy v1 API returns two distinct error-body shapes, both handled
  # here:
  #
  # - Framework errors: `{"name":"Not Found","message":"Página não encontrada.","code":0,"status":404}`
  # - Application envelopes: `{"status":404,"data":null,"message":"Template não encontrado."}`
  #
  # @example Rescue an API error
  #   begin
  #     client.documents.details('missing-id')
  #   rescue Assinafy::ApiError => e
  #     e.status_code   # => 404
  #     e.message       # => "Documento não encontrado."
  #     e.error_name    # => "Not Found" (nil when the body omits it)
  #     e.error_code    # => 0          (nil when the body omits it)
  #     e.response_data # => the raw parsed body Hash
  #   end
  class ApiError < Error
    # @return [Integer] HTTP-style status code reported by the API
    attr_reader :status_code
    # @return [Hash, String, nil] raw response body
    attr_reader :response_data
    # @return [String, nil] the API's `name` field (framework errors only)
    attr_reader :error_name
    # @return [Integer, String, nil] the API's `code` field, when present
    attr_reader :error_code

    def initialize(message, status_code, response_data = nil)
      super(message, { status_code: status_code, response_data: response_data })
      @status_code   = status_code
      @response_data = response_data
      return unless response_data.is_a?(Hash)

      @error_name = response_data['name']
      @error_code = response_data['code']
    end

    # Build an {ApiError} from an HTTP status and parsed body. Reads the human
    # message from `message`, `error`, or `name` (in that order).
    #
    # @param status_code   [Integer]
    # @param response_data [Hash, Object]
    # @return [ApiError]
    def self.from_response(status_code, response_data)
      data = response_data.is_a?(Hash) ? response_data : {}
      message = data['message'] || data['error'] || data['name'] || 'API request failed'
      new(message.to_s, status_code, response_data)
    end
  end

  # Raised before a network request is made when the caller's input is
  # invalid (missing IDs, wrong shape, etc.).
  class ValidationError < Error
    # @return [Hash] field-keyed validation details
    attr_reader :errors

    def initialize(message = 'Validation failed', errors = {})
      super(message, { errors: errors })
      @errors = errors || {}
    end
  end

  # Raised when Faraday reports a connection error or a timeout. The
  # original exception's message is included.
  class NetworkError < Error; end
end
