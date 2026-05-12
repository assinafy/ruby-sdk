# frozen_string_literal: true

# Coverage matrix: every documented Assinafy v1 endpoint mapped to the
# SDK method that wraps it. This spec exists so the audit is checked into
# version control and runs in CI — adding a new endpoint without wiring it
# into the SDK will cause this file to be edited deliberately.
#
# Source of truth: https://api.assinafy.com.br/v1/docs

RSpec.describe Assinafy::Client, type: :coverage_matrix do
  let(:endpoints) do
    [
      # Authentication
      ['POST',   '/login',
       'AuthResource#login'],
      ['POST',   '/authentication/social-login',
       'AuthResource#social_login'],
      ['POST',   '/users/api-keys',
       'AuthResource#create_api_key'],
      ['GET',    '/users/api-keys',
       'AuthResource#get_api_key'],
      ['DELETE', '/users/api-keys',
       'AuthResource#delete_api_key'],
      ['PUT',    '/authentication/change-password',
       'AuthResource#change_password'],
      ['PUT',    '/authentication/request-password-reset',
       'AuthResource#request_password_reset'],
      ['PUT',    '/authentication/reset-password',
       'AuthResource#reset_password'],

      # Signers — workspace CRUD
      ['POST',   '/accounts/{account_id}/signers',
       'SignerResource#create'],
      ['GET',    '/accounts/{account_id}/signers',
       'SignerResource#list'],
      ['GET',    '/accounts/{account_id}/signers/{signer_id}',
       'SignerResource#get'],
      ['PUT',    '/accounts/{account_id}/signers/{signer_id}',
       'SignerResource#update'],
      ['DELETE', '/accounts/{account_id}/signers/{signer_id}',
       'SignerResource#delete'],

      # Signer self-service
      ['GET',    '/signers/self',
       'SignerResource#self_data'],
      ['PUT',    '/signers/accept-terms',
       'SignerResource#accept_terms'],
      ['POST',   '/verify',
       'SignerResource#verify_email'],
      ['PUT',    '/documents/{documentId}/signers/confirm-data',
       'SignerResource#confirm_data'],

      # Signature upload/download
      ['POST',   '/signature',
       'SignerResource#upload_signature'],
      ['GET',    '/signature/{type}',
       'SignerResource#download_signature'],

      # Documents
      ['GET',    '/documents/statuses',
       'DocumentResource#statuses'],
      ['GET',    '/accounts/{account_id}/documents',
       'DocumentResource#list'],
      ['POST',   '/accounts/{account_id}/documents',
       'DocumentResource#upload'],
      ['POST',   '/accounts/{account_id}/templates/{template_id}/documents',
       'DocumentResource#create_from_template'],
      ['POST',   '/accounts/{account_id}/templates/{template_id}/documents/estimate-cost',
       'DocumentResource#estimate_cost_from_template'],
      ['GET',    '/documents/{document_id}',
       'DocumentResource#details'],
      ['DELETE', '/documents/{documentId}',
       'DocumentResource#delete'],
      ['GET',    '/documents/{document_id}/download/{artifact_name}',
       'DocumentResource#download'],
      ['GET',    '/documents/{document_id}/thumbnail',
       'DocumentResource#thumbnail'],
      ['GET',    '/documents/{document_id}/pages/{page_id}/download',
       'DocumentResource#download_page'],
      ['GET',    '/documents/{signature_hash}/verify',
       'DocumentResource#verify'],
      ['GET',    '/documents/{documentId}/activities',
       'DocumentResource#activities'],
      ['GET',    '/public/documents/{document_id}',
       'DocumentResource#public_info'],
      ['PUT',    '/public/documents/{document_id}/send-token',
       'DocumentResource#send_token'],

      # Templates
      ['GET',    '/accounts/{account_id}/templates',
       'TemplateResource#list'],
      ['GET',    '/accounts/{account_id}/templates/{template_id}',
       'TemplateResource#get'],
      ['POST',   '/accounts/{account_id}/templates',
       'TemplateResource#create'],
      ['PUT',    '/accounts/{account_id}/templates/{template_id}',
       'TemplateResource#update'],

      # Assignments
      ['POST',   '/documents/{documentId}/assignments',
       'AssignmentResource#create'],
      ['POST',   '/documents/{documentId}/assignments/estimate-cost',
       'AssignmentResource#estimate_cost'],
      ['PUT',    '/documents/{documentId}/assignments/{assignmentId}/reset-expiration',
       'AssignmentResource#reset_expiration'],
      ['PUT',    '/documents/{documentId}/assignments/{assignmentId}/signers/{signerId}/resend',
       'AssignmentResource#resend_notification'],
      ['POST',   '/documents/{documentId}/assignments/{assignmentId}/signers/{signerId}/estimate-resend-cost',
       'AssignmentResource#estimate_resend_cost'],
      ['GET',    '/sign',
       'AssignmentResource#signer_document'],
      ['POST',   '/documents/{documentId}/assignments/{assignmentId}',
       'AssignmentResource#sign'],
      ['PUT',    '/documents/{documentId}/assignments/{assignmentId}/reject',
       'AssignmentResource#decline'],
      ['GET',    '/documents/{documentId}/assignments/{assignmentId}/whatsapp-notifications',
       'AssignmentResource#whatsapp_notifications'],

      # Signer documents (signer-access-code authenticated)
      ['GET',    '/signers/{signer_id}/document',
       'SignerDocumentResource#current'],
      ['GET',    '/signers/{signer_id}/documents',
       'SignerDocumentResource#list'],
      ['PUT',    '/signers/documents/sign-multiple',
       'SignerDocumentResource#sign_multiple'],
      ['PUT',    '/signers/documents/decline-multiple',
       'SignerDocumentResource#decline_multiple'],
      ['GET',    '/signers/{signer_id}/documents/{document_id}/download/{artifact_name}',
       'SignerDocumentResource#download'],

      # Fields
      ['POST',   '/accounts/{account_id}/fields',
       'FieldResource#create'],
      ['GET',    '/accounts/{account_id}/fields',
       'FieldResource#list'],
      ['GET',    '/accounts/{account_id}/fields/{field_id}',
       'FieldResource#get'],
      ['PUT',    '/accounts/{account_id}/fields/{field_id}',
       'FieldResource#update'],
      ['DELETE', '/accounts/{account_id}/fields/{field_id}',
       'FieldResource#delete'],
      ['POST',   '/accounts/{account_id}/fields/{field_id}/validate',
       'FieldResource#validate'],
      ['POST',   '/accounts/{account_id}/fields/validate-multiple',
       'FieldResource#validate_multiple'],
      ['GET',    '/field-types',
       'FieldResource#types'],

      # Webhooks
      ['GET',    '/accounts/{account_id}/webhooks/subscriptions',
       'WebhookResource#get'],
      ['PUT',    '/accounts/{account_id}/webhooks/subscriptions',
       'WebhookResource#register'],
      ['DELETE', '/accounts/{account_id}/webhooks/subscriptions',
       'WebhookResource#delete'],
      ['PUT',    '/accounts/{account_id}/webhooks/inactivate',
       'WebhookResource#inactivate'],
      ['GET',    '/webhooks/event-types',
       'WebhookResource#list_event_types'],
      ['GET',    '/accounts/{account_id}/webhooks',
       'WebhookResource#list_dispatches'],
      ['POST',   '/accounts/{account_id}/webhooks/{dispatch_id}/retry',
       'WebhookResource#retry_dispatch']
    ]
  end

  it 'covers every documented endpoint with a single SDK method' do
    aggregate_failures do
      endpoints.each do |(verb, path, mapping)|
        class_name, method_name = mapping.split('#')
        klass = Assinafy::Resources.const_get(class_name)
        expect(klass.public_instance_methods(false)).to(
          include(method_name.to_sym),
          "#{verb} #{path} -> missing #{mapping}"
        )
      end
    end
  end

  it 'has at least one wrapper per documented endpoint and no orphan resources' do
    documented_classes = endpoints.map { |(_, _, m)| m.split('#').first }.uniq.sort
    sdk_resources = Assinafy::Resources.constants
                                       .map(&:to_s)
                                       .reject { |c| c == 'BaseResource' }
                                       .sort

    expect(documented_classes).to eq(sdk_resources)
  end
end
