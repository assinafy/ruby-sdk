# frozen_string_literal: true

module Assinafy
  class Error < StandardError
    attr_reader :context

    def initialize(message = nil, context = {})
      super(message)
      @context = context || {}
    end
  end

  class ApiError < Error
    attr_reader :status_code, :response_data

    def initialize(message, status_code, response_data = nil)
      super(message, { status_code: status_code, response_data: response_data })
      @status_code = status_code
      @response_data = response_data
    end

    def self.from_response(status_code, response_data)
      data = response_data.is_a?(Hash) ? response_data : {}
      message = data['message'] || data['error'] || 'API request failed'
      new(message.to_s, status_code, response_data)
    end
  end

  class ValidationError < Error
    attr_reader :errors

    def initialize(message = 'Validation failed', errors = {})
      super(message, { errors: errors })
      @errors = errors || {}
    end
  end

  class NetworkError < Error; end
end
