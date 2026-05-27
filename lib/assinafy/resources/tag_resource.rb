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
      # List tags in the workspace.
      #
      # @param params [Hash] query parameters (`search`, `page`, `per_page`)
      # @param account_id_override [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [...], meta: { ... } }`
      # @see GET /accounts/{account_id}/tags
      def list(params = {}, account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_list('Failed to list tags') do
          http_get("accounts/#{acc_id}/tags", params)
        end
      end

      # Create a tag in the workspace.
      #
      # @param payload [Hash]
      # @option payload [String] :name  required tag display name
      # @option payload [String, nil] :color optional 6-character hex color
      # @param account_id_override [String, nil]
      # @return [Hash]
      # @see POST /accounts/{account_id}/tags
      def create(payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        body   = tag_payload(payload, require_name: true)

        call('Failed to create tag') do
          http_post("accounts/#{acc_id}/tags", body)
        end
      end

      # Update a tag's name and/or color.
      #
      # @param tag_id [String]
      # @param payload [Hash]
      # @option payload [String] :name optional new name
      # @option payload [String, nil] :color optional new color; nil clears it
      # @param account_id_override [String, nil]
      # @return [Hash]
      # @see PUT /accounts/{account_id}/tags/{tag_id}
      def update(tag_id, payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        tid    = require_id(tag_id, 'Tag ID')
        body   = tag_payload(payload, require_name: false)

        call('Failed to update tag') do
          http_put("accounts/#{acc_id}/tags/#{tid}", body)
        end
      end

      # Delete a tag. Pass `force: true` to detach it from documents and
      # templates before deletion, matching the documented query parameter.
      #
      # @param tag_id [String]
      # @param account_id_override [String, nil]
      # @param force [Boolean]
      # @return [Hash]
      # @see DELETE /accounts/{account_id}/tags/{tag_id}
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
        name = body['name']

        body['color'] = nil if explicit_nil_color?(raw)

        if require_name && name.to_s.strip.empty?
          raise ValidationError.new('Tag name is required')
        end

        body
      end

      def explicit_nil_color?(payload)
        (payload.key?(:color) && payload[:color].nil?) ||
          (payload.key?('color') && payload['color'].nil?)
      end
    end
  end
end
