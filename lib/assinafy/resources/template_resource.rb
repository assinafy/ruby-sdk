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
      # @param params [Hash] `status`, `search`, `tags` (comma-separated IDs, AND), `sort`, `page`, `per_page`
      # @param account_id_override [String, nil]
      # @return [Hash{Symbol=>Array,Hash}] `{ data: [Template, ...], meta: { current_page:, per_page:, ... } }`
      # @see GET /accounts/{account_id}/templates
      #
      # @example List ready templates and read pagination metadata
      #   client.templates.list(status: 'ready', per_page: 3)
      #   # Returns the unwrapped { data:, meta: } payload:
      #   # {
      #   #   data: [
      #   #     {
      #   #       "id" => "fa7f3e524f3a2cc00a5ea4325e2",
      #   #       "name" => "sample-contract-one-page.pdf",
      #   #       "document_name" => "sample-contract-one-page.pdf",
      #   #       "message" => nil,
      #   #       "status" => "Ready",
      #   #       "pages" => [{ "id" => "fa7f3e528d77f2b3ed786df2ce0", "number" => 1, "fields" => [] }],
      #   #       "roles" => [{ "id" => "fa7f3e525bfefc71df3701eac6f", "name" => "Editor" }],
      #   #       "tags" => [{ "id" => "fa8c09f3e709a8a1c82d69b1454", "name" => "HR" }],
      #   #       "created_at" => "2024-07-19T15:23:03Z",
      #   #       "updated_at" => "2024-07-19T15:23:03Z"
      #   #     }
      #   #     # ... (each entry is a Template Object; see docs for full shape)
      #   #   ],
      #   #   meta: { current_page: 1, per_page: 3, total: 0, last_page: 0 }
      #   # }
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
      # @return [Hash] the unwrapped Template Object
      # @see GET /accounts/{account_id}/templates/{template_id}
      #
      # @example Fetch a single template (includes default_document_tags, omitted from #list)
      #   client.templates.get('fa7f3e524f3a2cc00a5ea4325e2')
      #   # Returns the unwrapped Template Object:
      #   # {
      #   #   "resource" => "template",
      #   #   "id" => "fa7f3e524f3a2cc00a5ea4325e2",
      #   #   "name" => "sample-contract-one-page.pdf",
      #   #   "document_name" => "sample-contract-one-page.pdf",
      #   #   "message" => nil,
      #   #   "status" => "Ready",
      #   #   "pages" => [
      #   #     {
      #   #       "id" => "fa7f3e528d77f2b3ed786df2ce0", "number" => 1, "height" => 2100, "width" => 1275,
      #   #       "download_url" => "https://api.assinafy.com.br/v1/accounts/1a/templates/.../pages/.../download",
      #   #       "fields" => []
      #   #     }
      #   #   ],
      #   #   "roles" => [{ "id" => "fa7f3e525bfefc71df3701eac6f", "name" => "Editor", "assignment_type" => "Editor" }],
      #   #   "tags" => [{ "id" => "fa8c09f3e709a8a1c82d69b1454", "name" => "HR" }],
      #   #   "default_document_tags" => [],
      #   #   "created_at" => "2024-07-19T15:23:03Z",
      #   #   "updated_at" => "2024-07-19T15:23:03Z"
      #   # }
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
      # @return [Hash] the unwrapped Template Object for the created template
      # @see POST /accounts/{account_id}/templates
      #
      # @example Create a template
      #   client.templates.create(name: 'Sales Contract', document_name: 'sales-contract.pdf')
      #   # JSON body sent: { "name": "Sales Contract", "document_name": "sales-contract.pdf" }
      #   # Returns the unwrapped Template Object:
      #   # {
      #   #   "resource" => "template",
      #   #   "id" => "fa7f3e524f3a2cc00a5ea4325e2",
      #   #   "name" => "Sales Contract",
      #   #   "document_name" => "sales-contract.pdf",
      #   #   "message" => nil,
      #   #   "status" => "uploading",
      #   #   "pages" => [],
      #   #   "roles" => [],
      #   #   "tags" => [],
      #   #   "created_at" => "2024-07-19T15:23:03Z",
      #   #   "updated_at" => "2024-07-19T15:23:03Z"
      #   # }
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
      # @return [Hash] the unwrapped Template Object for the updated template
      # @see PUT /accounts/{account_id}/templates/{template_id}
      #
      # @example Rename a template and set its default invitation message
      #   client.templates.update('fa7f3e524f3a2cc00a5ea4325e2', name: 'Renamed', message: 'Please sign')
      #   # JSON body sent: { "name": "Renamed", "message": "Please sign" }
      #   # Returns the unwrapped Template Object:
      #   # {
      #   #   "resource" => "template",
      #   #   "id" => "fa7f3e524f3a2cc00a5ea4325e2",
      #   #   "name" => "Renamed",
      #   #   "document_name" => "sample-contract-one-page.pdf",
      #   #   "message" => "Please sign",
      #   #   "status" => "Ready",
      #   #   "created_at" => "2024-07-19T15:23:03Z",
      #   #   "updated_at" => "2024-07-19T16:00:00Z"
      #   #   # ... (full Template Object: pages, roles, tags; see docs for full shape)
      #   # }
      def update(template_id, payload, account_id_override = nil)
        acc_id  = account_id(account_id_override)
        tmpl_id = require_id(template_id, 'Template ID')
        body    = body_params(require_payload(payload, 'Template payload'))

        call('Failed to update template') do
          http_put("accounts/#{acc_id}/templates/#{tmpl_id}", body)
        end
      end

      # Delete a template.
      #
      # @param template_id         [String]
      # @param account_id_override [String, nil]
      # @return [nil] always nil on success (the SDK discards the envelope body)
      # @raise [Assinafy::ApiError] 404 "Template não encontrado." when the template ID does not exist
      # @see DELETE /accounts/{account_id}/templates/{template_id}
      #
      # @example Delete a template
      #   client.templates.delete('fa7f3e524f3a2cc00a5ea4325e2')
      #   # => nil
      #
      # @example Deleting an unknown template raises
      #   client.templates.delete('does-not-exist')
      #   # raises Assinafy::ApiError (status 404, message "Template não encontrado.")
      def delete(template_id, account_id_override = nil)
        acc_id  = account_id(account_id_override)
        tmpl_id = require_id(template_id, 'Template ID')

        call_void('Failed to delete template') do
          http_delete("accounts/#{acc_id}/templates/#{tmpl_id}")
        end
      end

      # Download a rendered template page image as raw bytes. The page IDs come
      # from the Template Page Objects on {#get} (each carries a `download_url`).
      #
      # @param template_id         [String]
      # @param page_id             [String]
      # @param account_id_override [String, nil]
      # @return [String] the raw image bytes (ASCII-8BIT/binary), not the JSON envelope
      # @raise [Assinafy::ApiError] 404 'Template "{id}" não encontrado.' when the template or page is unknown
      # @see GET /accounts/{account_id}/templates/{template_id}/pages/{page_id}/download
      #
      # @example Download a page image and write it to disk
      #   bytes = client.templates.download_page('fa7f3e524f3a2cc00a5ea4325e2', 'fa7f3e528d77f2b3ed786df2ce0')
      #   # => "\x89PNG\r\n\x1A\n..." (raw binary String, encoding ASCII-8BIT)
      #   File.binwrite('page-1.png', bytes)
      #
      # @example Downloading an unknown page raises
      #   client.templates.download_page('bad-id', 'bad-page')
      #   # raises Assinafy::ApiError (status 404, message 'Template "{id}" não encontrado.')
      def download_page(template_id, page_id, account_id_override = nil)
        acc_id  = account_id(account_id_override)
        tmpl_id = require_id(template_id, 'Template ID')
        pid     = require_id(page_id, 'Page ID')

        call_binary('Failed to download template page') do
          http_get("accounts/#{acc_id}/templates/#{tmpl_id}/pages/#{pid}/download")
        end
      end
    end
  end
end
