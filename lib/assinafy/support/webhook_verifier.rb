# frozen_string_literal: true

require 'openssl'
require 'json'

module Assinafy
  module Support
    class WebhookVerifier
      def initialize(webhook_secret = nil)
        @webhook_secret = webhook_secret
      end

      def verify(payload, signature)
        return false unless @webhook_secret && !@webhook_secret.empty?
        return false unless signature && !signature.to_s.strip.empty?

        body     = payload.is_a?(String) ? payload : payload.to_s
        expected = OpenSSL::HMAC.hexdigest('SHA256', @webhook_secret, body)
        provided = signature.to_s.strip

        secure_compare(expected, provided)
      rescue StandardError
        false
      end

      def extract_event(payload)
        text   = payload.is_a?(String) ? payload : payload.to_s
        parsed = JSON.parse(text)
        parsed.is_a?(Hash) ? parsed : nil
      rescue JSON::ParserError
        nil
      end

      def event_type(event)
        return nil unless event.is_a?(Hash)

        event['event'] || event['type']
      end

      def event_data(event)
        return {} unless event.is_a?(Hash)

        event['data'] || event['object'] || {}
      end

      private

      def secure_compare(a, b)
        return false if a.bytesize != b.bytesize

        result = 0
        a.bytes.zip(b.bytes) { |x, y| result |= x ^ y }
        result.zero?
      end
    end
  end
end
