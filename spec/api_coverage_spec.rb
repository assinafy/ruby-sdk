# frozen_string_literal: true

# Static coverage matrix: current Assinafy v1 OpenAPI operations plus known
# sandbox-live template routes, each mapped to its SDK wrapper. This spec checks
# the committed inventory; it does not fetch or compare the remote OpenAPI file.
#
# OpenAPI reference: https://api.assinafy.com.br/v1/docs/openapi.json

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
      ['POST',   '/auth/link-social-login',
       'AuthResource#link_social_login'],

      # Accounts
      ['GET',    '/accounts',
       'AccountResource#list'],
      ['POST',   '/accounts',
       'AccountResource#create'],
      ['GET',    '/accounts/{account_id}',
       'AccountResource#get'],
      ['PUT',    '/accounts/{account_id}',
       'AccountResource#update'],
      ['DELETE', '/accounts/{account_id}',
       'AccountResource#delete'],
      ['GET',    '/accounts/{account_id}/theme',
       'AccountResource#theme'],
      ['GET',    '/accounts/{account_id}/stats',
       'AccountResource#stats'],
      ['GET',    '/accounts/{account_id}/logo',
       'AccountResource#download_logo'],
      ['POST',   '/accounts/{account_id}/logo',
       'AccountResource#upload_logo'],
      ['DELETE', '/accounts/{account_id}/logo',
       'AccountResource#delete_logo'],

      # Users (self)
      ['GET',    '/users/self',
       'UserResource#me'],
      ['GET',    '/users/self/stats',
       'UserResource#stats'],
      ['GET',    '/users/self/notification-preferences',
       'UserResource#notification_preferences'],
      ['PUT',    '/users/self/notification-preferences',
       'UserResource#update_notification_preferences'],

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
      ['GET',    '/accounts/{account_id}/documents/search',
       'DocumentResource#search'],
      ['POST',   '/accounts/{account_id}/documents',
       'DocumentResource#upload'],
      ['PATCH',  '/documents/{document_id}',
       'DocumentResource#rename'],
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
      ['GET',    '/accounts/{account_id}/documents/{document_id}/tags',
       'DocumentResource#list_tags'],
      ['PUT',    '/accounts/{account_id}/documents/{document_id}/tags',
       'DocumentResource#replace_tags'],
      ['POST',   '/accounts/{account_id}/documents/{document_id}/tags',
       'DocumentResource#append_tags'],
      ['DELETE', '/accounts/{account_id}/documents/{document_id}/tags/{tag_id}',
       'DocumentResource#detach_tag'],

      # Templates
      ['GET',    '/accounts/{account_id}/templates',
       'TemplateResource#list'],
      ['GET',    '/accounts/{account_id}/templates/{template_id}',
       'TemplateResource#get'],
      ['POST',   '/accounts/{account_id}/templates',
       'TemplateResource#create'],
      ['PUT',    '/accounts/{account_id}/templates/{template_id}',
       'TemplateResource#update'],
      ['DELETE', '/accounts/{account_id}/templates/{template_id}',
       'TemplateResource#delete'],
      ['GET',    '/accounts/{account_id}/templates/{template_id}/pages/{page_id}/download',
       'TemplateResource#download_page'],

      # Tags
      ['GET',    '/accounts/{account_id}/tags',
       'TagResource#list'],
      ['POST',   '/accounts/{account_id}/tags',
       'TagResource#create'],
      ['PUT',    '/accounts/{account_id}/tags/{tag_id}',
       'TagResource#update'],
      ['DELETE', '/accounts/{account_id}/tags/{tag_id}',
       'TagResource#delete'],

      # Assignments
      ['GET',    '/assignments',
       'AssignmentResource#list'],
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
      ['GET',    '/signers/{signer_id}/documents/search',
       'SignerDocumentResource#search'],
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

  # Public methods that intentionally do NOT map 1:1 to an API route:
  # convenience helpers (computed client-side) and documented aliases.
  let(:non_endpoint_methods) do
    {
      'DocumentResource'       => %i[get fully_signed? signing_progress wait_until_ready],
      'SignerResource'         => %i[find_by_email validate_create!],
      'SignerDocumentResource' => %i[document],
      'AuthResource'           => %i[api_key],
      'WebhookResource'        => %i[update]
    }
  end

  # Aliases asserted to resolve to their canonical method, so alias drift fails CI.
  let(:aliases) do
    {
      'DocumentResource'       => { get: :details },
      'SignerDocumentResource' => { document: :current },
      'AuthResource'           => { api_key: :get_api_key },
      'WebhookResource'        => { update: :register }
    }
  end

  it 'maps every listed operation to a public SDK method' do
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

  it 'lists each operation and SDK wrapper exactly once' do
    operations = endpoints.map do |verb, path, _mapping|
      [verb, path.gsub(/\{[^}]+\}/, '{}')]
    end
    wrappers = endpoints.map(&:last)

    expect(operations).to eq(operations.uniq)
    expect(wrappers).to eq(wrappers.uniq)
  end

  it 'has no public endpoint wrapper missing from the coverage matrix' do
    by_class = endpoints.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(_, _, m), acc|
      klass, meth = m.split('#')
      acc[klass] << meth.to_sym
    end

    aggregate_failures do
      Assinafy::Resources.constants.map(&:to_s).reject { |c| c == 'BaseResource' }.each do |class_name|
        klass     = Assinafy::Resources.const_get(class_name)
        mapped    = by_class[class_name]
        allowed   = non_endpoint_methods.fetch(class_name, [])
        unmapped  = klass.public_instance_methods(false) - mapped - allowed

        expect(unmapped).to(
          be_empty,
          "#{class_name} has public methods absent from the coverage matrix " \
          "(add a matrix row or list as a helper/alias): #{unmapped.inspect}"
        )
      end
    end
  end

  it 'keeps documented aliases pointing at their canonical methods' do
    aggregate_failures do
      aliases.each do |class_name, pairs|
        klass = Assinafy::Resources.const_get(class_name)
        pairs.each do |alias_name, canonical|
          expect(klass.instance_method(alias_name)).to(
            eq(klass.instance_method(canonical)),
            "#{class_name}##{alias_name} should alias ##{canonical}"
          )
        end
      end
    end
  end

  it 'has no orphan resource classes' do
    mapped_classes = endpoints.map { |(_, _, m)| m.split('#').first }.uniq.sort
    sdk_resources = Assinafy::Resources.constants
                                       .map(&:to_s)
                                       .reject { |c| c == 'BaseResource' }
                                       .sort

    expect(mapped_classes).to eq(sdk_resources)
  end
end
