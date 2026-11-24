# frozen_string_literal: true

module Assinafy
  module Resources
    # Pending assignment/envelope requests. Available on staging; all operations require documents:write.
    class ScheduledSendResource < BaseResource
      class << self
        # Validate the delivery window for a scheduled request.
        # @param value [String, Integer] ISO 8601 timestamp (no offset means UTC), or Unix seconds
        # @return [Time] the scheduled instant, from one hour to 90 days ahead
        # @raise [ValidationError] on an invalid timestamp or delivery window
        # @example
        #   Assinafy::Resources::ScheduledSendResource.require_send_at((Time.now + 7200).to_i) # => Time two hours ahead
        def require_send_at(value)
          time = schedule_time(value, 'send_at')
          now = Time.now
          unless time.between?(now + 3600, now + (90 * 86_400))
            raise ValidationError.new('send_at must be from one hour to 90 days ahead')
          end

          time
        end

        # Normalize a scheduled deadline for the ordinary assignment validators.
        # @param value [String, Integer, nil] ISO 8601 timestamp or Unix seconds; nil means no deadline
        # @param send_time [Time] validated send_at instant
        # @return [String, nil] zoned ISO 8601 deadline, at least two hours after send_at
        # @raise [ValidationError] on an invalid deadline
        # @example
        #   Assinafy::Resources::ScheduledSendResource.scheduled_expiration(nil, Time.now + 7200) # => nil
        def scheduled_expiration(value, send_time)
          return nil if value.nil?

          time = schedule_time(value, 'expires_at')
          raise ValidationError.new('expires_at must be at least two hours after send_at') if time < send_time + 7200

          return time.utc.iso8601 if value.is_a?(Integer)

          value.match?(/(?:Z|[+-]\d{2}:\d{2})\z/) ? value : "#{value}Z"
        end

        private

        def schedule_time(value, name)
          return Time.at(value).utc if value.is_a?(Integer)
          if value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?
                                                (?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)?\z/x)
            return DateTime.iso8601(value).to_time
          end

          raise ArgumentError
        rescue ArgumentError, RangeError
          raise ValidationError.new("#{name} must be an ISO 8601 timestamp or Unix seconds")
        end
      end

      # @param params [Hash] document_id, page and per_page
      # @param account_id_override [String, nil]
      # @return [Hash] paginated ScheduledSend objects, newest first, including terminal states
      # @raise [ValidationError] on invalid IDs or filters
      # @raise [ApiError, NetworkError] on API or transport failure
      # @see GET /accounts/{accountId}/scheduled-sends
      # @example
      #   client.scheduled_sends.list(document_id: 'document-id', per_page: 20)
      #   # GET .../scheduled-sends?document_id=document-id&per-page=20; no body
      #   # => { data: [{ 'resource' => 'scheduled_send', 'id' => 'send-id', 'type' => 'assignment',
      #   #      'document_ids' => ['document-id'], 'status' => 'pending', 'send_at' => '2026-12-01T12:00:00Z',
      #   #      'assignment_id' => nil, 'envelope_id' => nil, 'failure_reason' => nil,
      #   #      'created_at' => '2026-12-01T10:00:00Z', 'processed_at' => nil }],
      #   #      meta: { current_page: 1, per_page: 20, total: 1, last_page: 1 } }
      def list(params = {}, account_id_override = nil)
        query = query_params(params)
        require_id(query['document_id'], 'Document ID') if query.key?('document_id')
        path = "accounts/#{account_id(account_id_override)}/scheduled-sends"
        call_list('Failed to list scheduled sends') { http_get(path, query) }
      end

      # Cancel a pending send without sending or charging. Other states answer 409.
      # @param scheduled_send_id [String]
      # @param account_id_override [String, nil]
      # @return [Hash] ScheduledSend, now cancelled
      # @raise [ValidationError] on invalid IDs
      # @raise [ApiError, NetworkError] on API or transport failure
      # @see PUT /accounts/{accountId}/scheduled-sends/{scheduledSendId}/cancel
      # @example
      #   client.scheduled_sends.cancel('send-id') # PUT; no body
      #   # => { 'resource' => 'scheduled_send', 'id' => 'send-id', 'type' => 'assignment',
      #   #      'document_ids' => ['document-id'], 'status' => 'cancelled', 'send_at' => '2026-12-01T12:00:00Z',
      #   #      'assignment_id' => nil, 'envelope_id' => nil, 'failure_reason' => nil,
      #   #      'created_at' => '2026-12-01T10:00:00Z', 'processed_at' => '2026-12-01T10:30:00Z' }
      def cancel(scheduled_send_id, account_id_override = nil)
        path = "#{scheduled_send_path(scheduled_send_id, account_id_override)}/cancel"
        call('Failed to cancel scheduled send') { http_put(path) }
      end

      # Send a pending request now, with the original member's permissions, balance and credit ceiling.
      # A refused request stays pending; cancel it to prevent a later scheduled attempt. Never retries.
      # @param scheduled_send_id [String]
      # @param account_id_override [String, nil]
      # @return [Hash] ScheduledSend, now sent, with assignment_id or envelope_id
      # @raise [ValidationError] on invalid IDs
      # @raise [ApiError, NetworkError] on API or transport failure, including 409 for a non-pending send
      # @see PUT /accounts/{accountId}/scheduled-sends/{scheduledSendId}/send
      # @example
      #   client.scheduled_sends.send_now('send-id') # PUT; no body
      #   # => { 'resource' => 'scheduled_send', 'id' => 'send-id', 'type' => 'assignment',
      #   #      'document_ids' => ['document-id'], 'status' => 'sent', 'send_at' => '2026-12-01T12:00:00Z',
      #   #      'assignment_id' => 'assignment-id', 'envelope_id' => nil, 'failure_reason' => nil,
      #   #      'created_at' => '2026-12-01T10:00:00Z', 'processed_at' => '2026-12-01T10:30:00Z' }
      def send_now(scheduled_send_id, account_id_override = nil)
        path = "#{scheduled_send_path(scheduled_send_id, account_id_override)}/send"
        call('Failed to send scheduled request') { http_put(path) }
      end

      private

      def scheduled_send_path(send_id, override)
        "accounts/#{account_id(override)}/scheduled-sends/#{require_id(send_id, 'Scheduled send ID')}"
      end
    end
  end
end
