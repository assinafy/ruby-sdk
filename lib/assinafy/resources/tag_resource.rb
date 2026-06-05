# frozen_string_literal: true

module Assinafy
  module Resources
    # Workspace-scoped tag management.
    #
    # Tags are labels that can be attached to documents and templates for
    # filtering and organization.
    #
    # See https://api.assinafy.com.br/v1/docs#tag for the full
    # documentation of these endpoints.
    class TagResource < BaseResource
      # List tags in the workspace, ordered alphabetically by name.
      #
      # @param params [Hash] query parameters (`search`, `page`, `per_page`)
      # @param account_id_override [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [...], meta: { ... } }`
      # @see GET /accounts/{account_id}/tags
      # @example List tags matching a search term
      #   # Request: GET /accounts/{account_id}/tags?search=doc&per_page=3
      #   client.tags.list(search: 'doc', per_page: 3)
      #
      #   # Response (unwrapped data payload):
      #   {
      #     data: [
      #       {
      #         'id' => '1031f6544019bafc410c6c5317f4',
      #         'name' => 'audit-doc-tag',
      #         'color' => nil,
      #         'created_at' => '2026-06-05T16:33:35Z',
      #         'updated_at' => '2026-06-05T16:33:35Z'
      #       }
      #       # ... (each entry also carries 'resource' => 'tag')
      #     ],
      #     meta: { current_page: 1, per_page: 3, total: 13, last_page: 5 }
      #   }
      def list(params = {}, account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_list('Failed to list tags') do
          http_get("accounts/#{acc_id}/tags", params)
        end
      end

      # Create a tag in the workspace.
      #
      # Returns 409 Conflict if a tag with the same name (case-insensitive)
      # already exists.
      #
      # @param payload [Hash]
      # @option payload [String] :name  required tag display name
      # @option payload [String, nil] :color optional 6-character hex color
      # @param account_id_override [String, nil]
      # @return [Hash] the created tag object
      # @raise [Assinafy::ValidationError] if `:name` is missing or blank
      # @see POST /accounts/{account_id}/tags
      # @example Create a tag
      #   # Request: POST /accounts/{account_id}/tags
      #   # Body: { "name": "Contracts", "color": "ff8800" }
      #   client.tags.create(name: 'Contracts', color: 'ff8800')
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'resource' => 'tag',
      #     'id' => '1032009e69e366ca5adc879ef26c',
      #     'name' => 'Contracts',
      #     'color' => 'ff8800',
      #     'created_at' => '2026-06-05T21:21:19Z',
      #     'updated_at' => '2026-06-05T21:21:19Z'
      #   }
      def create(payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        body   = tag_payload(payload, require_name: true)

        call('Failed to create tag') do
          http_post("accounts/#{acc_id}/tags", body)
        end
      end

      # Update a tag's name and/or color. Documents and templates already
      # attached to the tag keep their relationship; only the tag's own
      # attributes change. Returns 409 Conflict if another tag already uses
      # the new name (case-insensitive).
      #
      # At least one of `:name` or `:color` must be supplied: an empty payload
      # raises, and a blank `:name` raises.
      #
      # @param tag_id [String]
      # @param payload [Hash]
      # @option payload [String] :name optional new name
      # @option payload [String, nil] :color optional new color; nil clears it
      # @param account_id_override [String, nil]
      # @return [Hash] the updated tag object
      # @raise [Assinafy::ValidationError] if the payload is empty or `:name` is blank
      # @see PUT /accounts/{account_id}/tags/{tag_id}
      # @example Rename a tag and recolor it
      #   # Request: PUT /accounts/{account_id}/tags/{tag_id}
      #   # Body: { "name": "Sales Contracts", "color": "112233" }
      #   client.tags.update('1032009e69e366ca5adc879ef26c',
      #                      name: 'Sales Contracts', color: '112233')
      #
      #   # Response (unwrapped data payload):
      #   {
      #     'resource' => 'tag',
      #     'id' => '1032009e69e366ca5adc879ef26c',
      #     'name' => 'Sales Contracts',
      #     'color' => '112233',
      #     'created_at' => '2026-06-05T21:21:19Z',
      #     'updated_at' => '2026-06-05T22:00:00Z'
      #   }
      # @example Clear a tag's color (pass nil explicitly)
      #   # Request: PUT /accounts/{account_id}/tags/{tag_id}
      #   # Body: { "color": null }
      #   client.tags.update('1032009e69e366ca5adc879ef26c', color: nil)
      #   #=> { 'resource' => 'tag', 'id' => '1032009e69e366ca5adc879ef26c', 'color' => nil, ... }
      def update(tag_id, payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        tid    = require_id(tag_id, 'Tag ID')
        body   = tag_payload(payload, require_name: false)

        call('Failed to update tag') do
          http_put("accounts/#{acc_id}/tags/#{tid}", body)
        end
      end

      # Delete a tag. By default, deletion fails with 409 Conflict if the tag
      # is attached to any document or template. Pass `force: true` to detach
      # it from everything and delete it; the documents and templates
      # themselves are not deleted.
      #
      # @param tag_id [String]
      # @param account_id_override [String, nil]
      # @param force [Boolean]
      # @return [Hash] `{ 'deleted' => true }`
      # @see DELETE /accounts/{account_id}/tags/{tag_id}
      # @example Delete a tag, detaching it from documents and templates first
      #   # Request: DELETE /accounts/{account_id}/tags/{tag_id}?force=true
      #   client.tags.delete('1032009e69e366ca5adc879ef26c', force: true)
      #
      #   # Response (unwrapped data payload):
      #   { 'deleted' => true }
      def delete(tag_id, account_id_override = nil, force: false)
        acc_id = account_id(account_id_override)
        tid    = require_id(tag_id, 'Tag ID')
        params = force ? { force: true } : {}

        call('Failed to delete tag') do
          http_delete("accounts/#{acc_id}/tags/#{tid}", params)
        end
      end

      private

      def tag_payload(payload, require_name:)
        raw  = require_payload(payload, 'Tag payload')
        body = body_params(raw)
        body['color'] = nil if explicit_nil_color?(raw)

        validate_tag_name!(body, require_name: require_name)

        if !require_name && body.empty?
          raise ValidationError.new('Provide at least one of name or color to update')
        end

        body
      end

      def validate_tag_name!(body, require_name:)
        has_name = body.key?('name')
        blank    = body['name'].to_s.strip.empty?

        raise ValidationError.new('Tag name is required') if require_name && (!has_name || blank)
        raise ValidationError.new('Tag name cannot be blank') if !require_name && has_name && blank
      end

      def explicit_nil_color?(payload)
        (payload.key?(:color) && payload[:color].nil?) ||
          (payload.key?('color') && payload['color'].nil?)
      end
    end
  end
end
