# frozen_string_literal: true

module Assinafy
  module Resources
    class TemplateResource < BaseResource
      def list(params = {}, account_id_override = nil)
        acc_id = account_id(account_id_override)

        call_list('Failed to list templates') do
          http_get("accounts/#{acc_id}/templates", params)
        end
      end

      def get(template_id, account_id_override = nil)
        acc_id  = account_id(account_id_override)
        tmpl_id = require_id(template_id, 'Template ID')

        call('Failed to fetch template') do
          http_get("accounts/#{acc_id}/templates/#{tmpl_id}")
        end
      end

      def create(payload, account_id_override = nil)
        acc_id = account_id(account_id_override)
        body   = body_params(require_payload(payload, 'Template payload'))

        call('Failed to create template') do
          http_post("accounts/#{acc_id}/templates", body)
        end
      end

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
