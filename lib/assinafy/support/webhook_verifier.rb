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
    #   # NOTE: the header below is one YOUR gateway injects (e.g. Cloudflare /
    #   # API Gateway). Assinafy v1 does not send a signature header itself.
    #   if verifier.verify(raw_body, request.headers['X-Webhook-Signature'])
    #     event = verifier.extract_event(raw_body)
    #     verifier.event_type(event)    # => "assignment_created"
    #     verifier.event_payload(event) # => { "user_name" => "John", ... } (or nil)
    #     verifier.event_object(event)  # => { "id" => "doc2", "type" => "Document", ... }
    #     verifier.event_subject(event) # => { "id" => "...", "type" => "User", ... }
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

      # Pull the event-type code from a parsed event Hash. The canonical key in
      # the Assinafy v1 delivery envelope is `event` (e.g. `assignment_created`).
      #
      # @param event [Hash, nil]
      # @return [String, nil]
      # @example
      #   verifier.event_type({ 'event' => 'document_ready' }) # => "document_ready"
      def event_type(event)
        return nil unless event.is_a?(Hash)

        event['event']
      end

      # The event-specific data snapshot (the documented top-level `payload`).
      # May be `nil` for events that carry no extra params (e.g.
      # `document_uploaded`).
      #
      # @param event [Hash, nil]
      # @return [Hash, nil]
      def event_payload(event)
        return nil unless event.is_a?(Hash)

        event['payload']
      end

      # The entity the event acted on (the documented top-level `object`),
      # e.g. the Document. Includes a `type` discriminator.
      #
      # @param event [Hash, nil]
      # @return [Hash]
      def event_object(event)
        return {} unless event.is_a?(Hash)

        event['object'] || {}
      end

      # The actor that triggered the event (the documented top-level `subject`),
      # e.g. the User. Includes a `type` discriminator.
      #
      # @param event [Hash, nil]
      # @return [Hash]
      def event_subject(event)
        return {} unless event.is_a?(Hash)

        event['subject'] || {}
      end

      # @deprecated Prefer {#event_payload} (event params) and {#event_object}
      #   (acted-on entity). The Assinafy envelope has no top-level `data` key;
      #   this returns `payload` and falls back to `object` for convenience.
      #
      # @param event [Hash, nil]
      # @return [Hash]
      def event_data(event)
        return {} unless event.is_a?(Hash)

        event['payload'] || event['object'] || {}
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
