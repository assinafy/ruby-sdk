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
  class ApiError < Error
    # @return [Integer] HTTP-style status code reported by the API
    attr_reader :status_code
    # @return [Hash, String, nil] raw response body
    attr_reader :response_data

    def initialize(message, status_code, response_data = nil)
      super(message, { status_code: status_code, response_data: response_data })
      @status_code = status_code
      @response_data = response_data
    end

    # Build an {ApiError} from an HTTP status and parsed body.
    #
    # @param status_code   [Integer]
    # @param response_data [Hash, Object]
    # @return [ApiError]
    def self.from_response(status_code, response_data)
      data = response_data.is_a?(Hash) ? response_data : {}
      message = data['message'] || data['error'] || 'API request failed'
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
