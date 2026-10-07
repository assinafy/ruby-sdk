# frozen_string_literal: true

require 'openssl'
require 'json'

module Assinafy
  module Support
    # Verifies webhook deliveries and reads their envelope.
    #
    # Assinafy signs deliveries to endpoints created with
    # `signing_enabled: true` following the Standard Webhooks specification
    # (https://www.standardwebhooks.com): the `webhook-signature` header holds
    # space-separated `v1,<base64 HMAC-SHA256>` entries over
    # `{webhook-id}.{webhook-timestamp}.{raw body}`, keyed with the base64 key
    # after the `whsec_` prefix of the endpoint secret. {#verify_delivery}
    # checks that signature and rejects stale timestamps to stop replays.
    # Deduplicate retries on the `webhook-id` header.
    #
    # {#verify} remains for receivers whose own gateway signs the raw body
    # with a hex HMAC-SHA256.
    #
    # @example Verify a signed delivery (Rack / Rails)
    #   secret   = client.webhooks.endpoint_secret('webhook-endpoint-id')[:secret]
    #   verifier = Assinafy::Support::WebhookVerifier.new(secret)
    #   raw_body = request.body.read
    #   return head(:unauthorized) unless verifier.verify_delivery(raw_body, request.headers)
    #
    #   event = verifier.extract_event(raw_body)
    #   verifier.event_type(event)    # => "assignment_created"
    #   verifier.event_payload(event) # => { "user_name" => "John", ... } (or nil)
    #   verifier.event_object(event)  # => { "id" => "doc2", "type" => "Document", ... }
    #   verifier.event_subject(event) # => { "id" => "...", "type" => "User", ... }
    class WebhookVerifier
      SECRET_PREFIX     = 'whsec_'
      DEFAULT_TOLERANCE = 300

      # @param webhook_secret [String, nil] the endpoint's `whsec_...` secret
      #   (or a gateway secret for {#verify}). When nil/empty, every
      #   verification returns false (safe-by-default).
      def initialize(webhook_secret = nil)
        @webhook_secret = webhook_secret.is_a?(String) ? webhook_secret.dup.freeze : webhook_secret
      end

      # Verify a Standard Webhooks delivery from Assinafy.
      #
      # @param payload   [String] raw HTTP body, exactly as received (never re-serialized JSON)
      # @param headers   [Hash, #each] request headers; `webhook-id`, `Webhook-Id` and Rack's
      #   `HTTP_WEBHOOK_ID` forms are all accepted
      # @param tolerance [Integer] maximum clock difference in seconds
      # @param now       [Integer] current Unix time, injectable for tests
      # @return [Boolean] true only for a matching signature with a fresh timestamp
      def verify_delivery(payload, headers, tolerance: DEFAULT_TOLERANCE, now: Time.now.to_i)
        key = signing_key
        return false unless key

        found      = normalize_headers(headers)
        id         = found['webhook-id']
        timestamp  = found['webhook-timestamp']
        signatures = found['webhook-signature']
        return false if [id, timestamp, signatures].any? { |value| value.to_s.empty? }
        return false unless fresh?(timestamp, tolerance, now)

        content  = "#{id}.#{timestamp}.#{payload}"
        expected = "v1,#{[OpenSSL::HMAC.digest('SHA256', key, content)].pack('m0')}"
        signatures.to_s.split.any? { |signature| OpenSSL.secure_compare(expected, signature) }
      rescue StandardError
        false
      end

      # Constant-time compare a gateway-supplied hex signature to the
      # HMAC-SHA256 of the raw payload. For Assinafy's own signatures use
      # {#verify_delivery}.
      #
      # @param payload   [String]  raw HTTP body
      # @param signature [String]  hex-encoded signature header value
      # @return [Boolean]
      def verify(payload, signature)
        secret = @webhook_secret
        return false unless secret && !secret.empty?
        return false unless signature && !signature.to_s.strip.empty?

        body     = payload.is_a?(String) ? payload : payload.to_s
        expected = OpenSSL::HMAC.hexdigest('SHA256', secret, body)
        provided = signature.to_s.strip

        OpenSSL.fixed_length_secure_compare(expected, provided)
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

      def signing_key
        secret = @webhook_secret
        return nil unless secret.is_a?(String) && secret.start_with?(SECRET_PREFIX)

        key = secret.delete_prefix(SECRET_PREFIX).unpack1('m0')
        key.empty? ? nil : key
      rescue ArgumentError
        nil
      end

      def normalize_headers(headers)
        headers.each_with_object({}) do |(name, value), found|
          found[name.to_s.downcase.delete_prefix('http_').tr('_', '-')] = value
        end
      end

      def fresh?(timestamp, tolerance, now)
        (now - Integer(timestamp.to_s, 10)).abs <= tolerance
      rescue ArgumentError
        false
      end
    end
  end
end
