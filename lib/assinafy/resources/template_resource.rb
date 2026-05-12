# frozen_string_literal: true

module Assinafy
  module Resources
    # Templates — reusable document blueprints with roles and field placements.
    #
    # See https://api.assinafy.com.br/v1/docs#template for the documentation
    # of the Template Object and its related endpoints.
    class TemplateResource < BaseResource
      # List templates with pagination metadata.
      #
      # @param params [Hash] `status`, `search`, `sort`, `page`, `per_page`
      # @param account_id_override [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [...], meta: { ... } }`
      # @see GET /accounts/{account_id}/templates
      def list(params = {}, account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_list('Failed to list templates') do
          http_get("accounts/#{acc_id}/templates", params)
        end
      end

      # Fetch a template by ID.
      #
      # @param template_id         [String]
      # @param account_id_override [String, nil]
      # @return [Hash]
      # @see GET /accounts/{account_id}/templates/{template_id}
      def get(template_id, account_id_override = nil)
        acc_id  = account_id(account_id_override)
        tmpl_id = require_id(template_id, 'Template ID')

        call('Failed to fetch template') do
          http_get("accounts/#{acc_id}/templates/#{tmpl_id}")
        end
      end

      # Create a template. Body fields map directly to the documented
      # {https://api.assinafy.com.br/v1/docs#template-object Template Object}.
      #
      # @param payload             [Hash]
      # @param account_id_override [String, nil]
      # @return [Hash]
      # @see POST /accounts/{account_id}/templates
      def create(payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        body   = body_params(require_payload(payload, 'Template payload'))

        call('Failed to create template') do
          http_post("accounts/#{acc_id}/templates", body)
        end
      end

      # Update a template.
      #
      # @param template_id         [String]
      # @param payload             [Hash]
      # @param account_id_override [String, nil]
      # @return [Hash]
      # @see PUT /accounts/{account_id}/templates/{template_id}
      def update(template_id, payload, account_id_override = nil)
        acc_id  = account_id(account_id_override)
        tmpl_id = require_id(template_id, 'Template ID')
        body    = body_params(require_payload(payload, 'Template payload'))

        call('Failed to update template') do
          http_put("accounts/#{acc_id}/templates/#{tmpl_id}", body)
        end
      end
    end
  end
end
