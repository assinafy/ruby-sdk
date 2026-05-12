# frozen_string_literal: true

require 'openssl'
require 'json'

module Assinafy
  module Support
    # Defensive helper for verifying webhook deliveries when your gateway or
    # proxy signs the body with an HMAC-SHA256 secret.
    #
    # The Assinafy v1 API itself does not currently document a
    # request-signing scheme for webhook deliveries, so this class is opt-in:
    # construct it with a secret only if you have one configured in front
    # of your webhook receiver (e.g. via API Gateway / Cloudflare).
    #
    # @example Verify and dispatch a webhook
    #   verifier = Assinafy::Support::WebhookVerifier.new(ENV['WEBHOOK_SECRET'])
    #   raw_body = request.body.read
    #   if verifier.verify(raw_body, request.headers['X-Assinafy-Signature'])
    #     event = verifier.extract_event(raw_body)
    #     puts verifier.event_type(event), verifier.event_data(event)
    #   end
    class WebhookVerifier
      # @param webhook_secret [String, nil] shared secret. When nil/empty,
      #   {#verify} always returns false (safe-by-default).
      def initialize(webhook_secret = nil)
        @webhook_secret = webhook_secret
      end

      # Constant-time compare the provided signature to the expected
      # HMAC-SHA256 of the raw payload.
      #
      # @param payload   [String]  raw HTTP body
      # @param signature [String]  hex-encoded signature header value
      # @return [Boolean]
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

      # Parse a JSON webhook body into a Hash, returning nil on malformed or
      # non-object payloads.
      #
      # @param payload [String]
      # @return [Hash, nil]
      def extract_event(payload)
        text   = payload.is_a?(String) ? payload : payload.to_s
        parsed = JSON.parse(text)
        parsed.is_a?(Hash) ? parsed : nil
      rescue JSON::ParserError
        nil
      end

      # Pull the event-type code from a parsed event Hash. Supports both the
      # documented `event` and the legacy `type` key.
      #
      # @param event [Hash, nil]
      # @return [String, nil]
      def event_type(event)
        return nil unless event.is_a?(Hash)

        event['event'] || event['type']
      end

      # Pull the event payload (Hash) from a parsed event. Supports the
      # documented top-level `data`/`object` keys.
      #
      # @param event [Hash, nil]
      # @return [Hash]
      def event_data(event)
        return {} unless event.is_a?(Hash)

        event['data'] || event['object'] || {}
      end

      private

      def secure_compare(a, b)
        return false if a.bytesize != b.bytesize

        result = 0
        a.bytes.zip(b.bytes) { |x, y| result |= x ^ y }
        result == 0
      end
    end
  end
end
