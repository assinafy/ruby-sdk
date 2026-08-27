# frozen_string_literal: true

require 'English'
require 'uri'

# End-to-end integration specs that exercise the SDK against the real Assinafy
# sandbox. They are excluded from the default suite and only run when:
#
#   ASSINAFY_LIVE=1 \
#   ASSINAFY_API_KEY=... \
#   ASSINAFY_ACCOUNT_ID=... \
#   ASSINAFY_TEST_EMAIL=recipient1@example.com \
#   ASSINAFY_TEST_EMAIL2=recipient2@example.com \
#   ASSINAFY_BASE_URL=https://sandbox.assinafy.com.br/v1 \
#   bundle exec rspec spec/integration
#
# They create and clean up real resources, and (for the assignment flow) send
# real signature-request emails to ASSINAFY_TEST_EMAIL / ASSINAFY_TEST_EMAIL2.
RSpec.describe 'Assinafy live sandbox', :live, order: :defined do # rubocop:disable RSpec/DescribeClass
  before do |example|
    sleep 5 if example.metadata[:live]
  end

  def build_client
    base_url = sandbox_base_url!
    required_env('ASSINAFY_TEST_EMAIL')
    required_env('ASSINAFY_TEST_EMAIL2')

    Assinafy::Client.create(
      required_env('ASSINAFY_API_KEY'),
      required_env('ASSINAFY_ACCOUNT_ID'),
      base_url: base_url
    )
  end

  def required_env(name)
    value = ENV.fetch(name)
    return value unless value.strip.empty?

    raise ArgumentError.new("#{name} must not be blank")
  end

  def sandbox_base_url!
    value = ENV.fetch('ASSINAFY_BASE_URL', 'https://sandbox.assinafy.com.br/v1')
    uri = URI.parse(value)
    valid = uri.is_a?(URI::HTTPS) && uri.host == 'sandbox.assinafy.com.br' && uri.port == 443 &&
            uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && uri.path.delete_suffix('/') == '/v1'
    return value if valid

    raise ArgumentError.new('Live integration specs require the HTTPS Assinafy sandbox URL')
  rescue URI::InvalidURIError
    raise ArgumentError.new('Live integration specs require a valid Assinafy sandbox URL')
  end

  def cleanup_resources(*steps)
    original_error = $ERROR_INFO
    failures = []

    steps.each do |label, action|
      action.call
    rescue StandardError => e
      failures << e
      warn "Cleanup failed for #{label}: #{e.class}: #{e.message}"
    end

    raise failures.first if original_error.nil? && failures.any?
  end

  def delete_template_when_ready(client, template_id)
    retry_conflict { client.templates.delete(template_id) }
  end

  def delete_document_when_ready(client, document_id)
    retry_conflict { client.documents.delete(document_id) }
  end

  def retry_conflict
    clock = Process::CLOCK_MONOTONIC
    deadline = Process.clock_gettime(clock) + 30

    while Process.clock_gettime(clock) < deadline
      begin
        return yield
      rescue Assinafy::ApiError => e
        remaining = deadline - Process.clock_gettime(clock)
        raise unless e.status_code == 409 && remaining.positive?

        sleep([1, remaining].min)
      end
    end

    raise Assinafy::Error.new('Timeout waiting for resource deletion')
  end

  def wait_for_template_ready(client, template_id)
    clock = Process::CLOCK_MONOTONIC
    deadline = Process.clock_gettime(clock) + 60

    while Process.clock_gettime(clock) < deadline
      template = client.templates.get(template_id)
      return template if template['status'].to_s.casecmp?('Ready')

      remaining = deadline - Process.clock_gettime(clock)
      break unless remaining > 0

      sleep([1, remaining].min)
    end

    raise Assinafy::ValidationError.new('Timeout waiting for template to be ready')
  end

  def sample_pdf(text = 'Assinafy SDK live test')
    objs = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
            '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] ' \
            '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>']
    stream = "BT /F1 18 Tf 72 700 Td (#{text}) Tj ET"
    objs << "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream"
    objs << '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
    pdf = +"%PDF-1.4\n"
    offsets = []
    objs.each_with_index do |obj, i|
      offsets << pdf.bytesize
      pdf << "#{i + 1} 0 obj\n#{obj}\nendobj\n"
    end
    xref = pdf.bytesize
    pdf << "xref\n0 #{objs.size + 1}\n0000000000 65535 f \n"
    offsets.each { |o| pdf << (format('%<off>010d 00000 n ', off: o) << "\n") }
    pdf << "trailer\n<< /Size #{objs.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF"
    pdf.b
  end

  # A real, minimal 1x1 PNG (the API validates the actual image bytes).
  def sample_png
    ['89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489' \
     '0000000d4944415478da6360000002000100005fe02fea7d4b1e70000000049454e44ae426082'].pack('H*')
  end

  def find_or_create_signer(client, full_name, email)
    existing = client.signers.find_by_email(email)
    return [existing['id'], false] if existing

    [client.signers.create(full_name: full_name, email: email)['id'], true]
  end

  def unique_test_email(email)
    local, domain = email.split('@', 2)
    "#{local}+sdk-live-#{rand(1_000_000)}@#{domain}"
  end

  let(:client)          { build_client }
  let(:primary_email)   { required_env('ASSINAFY_TEST_EMAIL') }
  let(:secondary_email) { required_env('ASSINAFY_TEST_EMAIL2') }

  context 'when enforcing safety guards', live: false do
    it 'rejects production and malformed base URLs before creating a client' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch)
        .with('ASSINAFY_BASE_URL', anything)
        .and_return('https://api.assinafy.com.br/v1')

      expect(Assinafy::Client).not_to receive(:create)
      expect { build_client }.to raise_error(ArgumentError, /sandbox URL/)
    end

    it 'requires both non-blank test recipients before creating a client' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch)
        .with('ASSINAFY_BASE_URL', anything)
        .and_return('https://sandbox.assinafy.com.br/v1')
      allow(ENV).to receive(:fetch).with('ASSINAFY_TEST_EMAIL').and_return('recipient1@example.com')
      allow(ENV).to receive(:fetch).with('ASSINAFY_TEST_EMAIL2').and_return(' ')

      expect(Assinafy::Client).not_to receive(:create)
      expect { build_client }.to raise_error(ArgumentError, /ASSINAFY_TEST_EMAIL2 must not be blank/)
    end
  end

  it 'fetches the authenticated user profile' do
    me = client.users.me
    expect(me['user']).to include('email')
    expect(me['accounts']).to be_an(Array)
  end

  it 'reads API key metadata without rotating or deleting the key' do
    api_key = client.auth.get_api_key
    expect([Hash, NilClass]).to include(api_key.class)
  end

  it 'lists accounts, reads the current account and its theme' do
    aggregate_failures do
      expect(client.accounts.list[:data]).to be_an(Array)
      expect(client.accounts.get).to include('id' => ENV.fetch('ASSINAFY_ACCOUNT_ID'))
      expect(client.accounts.theme).to include('account_name')
    end
  end

  it 'runs the full account + logo lifecycle on a throwaway account' do
    id = nil

    begin
      acc = client.accounts.create(name: "sdk-live-#{rand(1_000_000)}")
      id = acc['id']
      expect(id).to be_a(String)

      upload = client.accounts.upload_logo({ buffer: sample_png, file_name: 'logo.png' }, id)
      aggregate_failures do
        expect(upload).to include('mime_type')
        expect(client.accounts.download_logo(id).bytesize).to be > 0
        expect(client.accounts.update({ name: 'sdk-live-renamed' }, id)['name']).to eq('sdk-live-renamed')
        expect(client.accounts.delete_logo(id)).to be_nil
        expect(client.accounts.delete(force: true, account_id_override: id)).to be_nil
      end
      id = nil # deleted cleanly above; nothing left for the ensure to reap
    ensure
      cleanup_resources(['account', -> { client.accounts.delete(force: true, account_id_override: id) if id }])
    end
  end

  it 'runs the document + assignment lifecycle (sends real emails)' do
    id = nil
    created_signer_ids = []

    begin
      upload_name = "sdk-live-#{rand(1_000_000)}.pdf"
      renamed_name = "sdk-live-renamed-#{rand(1_000_000)}.pdf"
      doc = client.documents.upload({ buffer: sample_pdf, file_name: upload_name })
      id = doc['id']
      ready = client.documents.wait_until_ready(id, max_wait_seconds: 30)
      search_results = client.documents.search(upload_name)[:data]
      renamed = client.documents.rename(id, renamed_name)
      page_id = ready.fetch('pages').first.fetch('id')

      s1, created_s1 = find_or_create_signer(client, 'SDK Live Signer One', primary_email)
      s2, created_s2 = find_or_create_signer(client, 'SDK Live Signer Two', secondary_email)
      created_signer_ids << s1 if created_s1
      created_signer_ids << s2 if created_s2

      estimate = client.assignments.estimate_cost(id, signers: [{ id: s1 }, { id: s2 }])
      assignment = client.assignments.create(
        id, signers: [{ id: s1 }, { id: s2 }], message: 'SDK live integration - please ignore'
      )
      aid = assignment['id']
      activities = client.documents.activities(id)
      upload_activity = activities.find { |activity| activity['event'] == 'document_uploaded' }

      aggregate_failures do
        expect(ready['status']).to eq('metadata_ready').or eq('pending_signature')
        expect(renamed['name']).to eq(renamed_name)
        expect(estimate).to include('has_sufficient_resources')
        expect(assignment['signers'].size).to eq(2)
        expect(assignment['signing_urls']).to be_an(Array)

        expect(client.documents.details(id)['id']).to eq(id)
        expect(search_results.map { |result| result['id'] }).to include(id)
        expect(client.documents.public_info(id)['id']).to eq(id)
        expect(activities).to be_an(Array)
        expect(upload_activity.dig('origin', 'user-agent')).to eq("Assinafy-Ruby-SDK/v#{Assinafy::VERSION}")
        expect(client.documents.thumbnail(id).bytesize).to be > 0
        expect(client.documents.download_page(id, page_id).bytesize).to be > 0
        expect(client.documents.download(id, 'original').byteslice(0, 4)).to eq('%PDF')
        expect(client.documents.list(per_page: 3)[:meta]).to include(:current_page)
        expect(client.assignments.list[:data].map { |a| a['id'] }).to include(aid)
        expect(client.assignments.whatsapp_notifications(id, aid)).to be_an(Array)
        expect(client.assignments.reset_expiration(id, aid, nil)['id']).to eq(aid)
        resend_estimate = client.assignments.estimate_resend_cost(id, aid, s1)
        expect(resend_estimate).to include('breakdown' => an_instance_of(Array), 'total' => a_kind_of(Numeric))
        expect(client.assignments.resend_notification(id, aid, s1)).to include('is_sent' => true)
        sent_token = client.documents.send_token(id, recipient: primary_email, channel: 'email')
        expect(sent_token).to include('channel' => 'email')
        expect(sent_token.dig('document', 'id')).to eq(id)
        expect(client.signer_documents.list(s1)[:data]).to be_an(Array)
        expect(client.signer_documents.search(s1, upload_name)[:data]).to be_an(Array)
        expect(client.signer_documents.download(s1, id, 'original').byteslice(0, 4)).to eq('%PDF')
      end
    ensure
      cleanup_resources(
        ['document', -> { delete_document_when_ready(client, id) if id }],
        *created_signer_ids.map { |signer_id| ['signer', -> { client.signers.delete(signer_id) }] }
      )
    end
  end

  it 'runs the high-level upload and signature-request workflow' do
    result = nil
    recovery = {}
    workflow_email = unique_test_email(primary_email)

    begin
      result = client.upload_and_request_signatures(
        source:  { buffer: sample_pdf('High-level workflow'), file_name: "sdk-flow-#{rand(9999)}.pdf" },
        signers: [{ full_name: 'SDK Workflow Signer', email: workflow_email }],
        message: 'SDK live integration - please ignore'
      )
      aggregate_failures do
        expect(result.dig(:document, 'id')).to be_a(String)
        expect(result.dig(:assignment, 'id')).to be_a(String)
        expect(result[:signer_ids]).to contain_exactly(a_kind_of(String))
      end
    rescue Assinafy::Error => e
      recovery = e.context
      raise
    ensure
      document = result&.dig(:document) || recovery[:document]
      signer_ids = result&.fetch(:signer_ids) || recovery.fetch(:signer_ids, [])
      cleanup_resources(
        ['document', -> { delete_document_when_ready(client, document['id']) if document&.[]('id') }],
        *signer_ids.map { |signer_id| ['signer', -> { client.signers.delete(signer_id) }] }
      )
    end
  end

  it 'runs the signer workspace CRUD lifecycle' do
    email = "sdk-live-#{rand(1_000_000)}@example.com"
    id = nil

    begin
      created = client.signers.create(full_name: 'SDK Live', email: email)
      id = created['id']
      aggregate_failures do
        expect(client.signers.get(id)['email']).to eq(email)
        expect(client.signers.update(id, full_name: 'SDK Live Renamed')['full_name']).to eq('SDK Live Renamed')
        expect(client.signers.list(per_page: 1)[:data]).to be_an(Array)
        expect(client.signers.find_by_email(email)['id']).to eq(id)
      end
    ensure
      cleanup_resources(['signer', -> { client.signers.delete(id) if id }])
    end
  end

  it 'runs the field definition + validation lifecycle' do
    id = nil

    begin
      field = client.fields.create(name: "SDK Live CPF #{rand(9999)}", type: 'cpf')
      id = field['id']
      aggregate_failures do
        expect(client.fields.get(id)['type']).to eq('cpf')
        expect(client.fields.update(id, name: 'SDK Live Renamed')['name']).to eq('SDK Live Renamed')
        expect(client.fields.validate(id, '000.000.000-00')).to include('success')
        multi = client.fields.validate_multiple([{ field_id: id, value: '00000000000' }])
        expect(multi.first).to include('field_id' => id)
        expect(client.fields.list[:data]).to be_an(Array)
        expect(client.fields.types).to be_an(Array)
      end
    ensure
      cleanup_resources(['field', -> { client.fields.delete(id) if id }])
    end
  end

  it 'runs the tag lifecycle and document attach/detach' do
    tag_id = nil
    doc_id = nil

    begin
      tag = client.tags.create(name: "sdk-live-#{rand(1_000_000)}", color: 'ff8800')
      tag_id = tag['id']
      doc = client.documents.upload({ buffer: sample_pdf, file_name: "sdk-tag-#{rand(9999)}.pdf" })
      doc_id = doc['id']
      client.documents.wait_until_ready(doc_id, max_wait_seconds: 30)

      aggregate_failures do
        expect(client.tags.list[:data]).to be_an(Array)
        expect(client.tags.update(tag_id, name: "#{tag['name']}-renamed")['name']).to end_with('-renamed')
        expect(client.documents.append_tags(doc_id, [tag_id])).to be_an(Array)
        expect(client.documents.replace_tags(doc_id, [tag_id])).to be_an(Array)
        expect(client.documents.list_tags(doc_id)).to be_an(Array)
        expect(client.documents.detach_tag(doc_id, tag_id)).to include('detached' => true)
      end
    ensure
      cleanup_resources(
        ['document', -> { delete_document_when_ready(client, doc_id) if doc_id }],
        ['tag', -> { client.tags.delete(tag_id) if tag_id }]
      )
    end
  end

  it 'reads webhook data and toggles an existing subscription' do
    original = client.webhooks.get

    begin
      aggregate_failures do
        expect(client.webhooks.list_event_types).to be_an(Array)
        expect(client.webhooks.list_dispatches(per_page: 2)[:data]).to be_an(Array)
        expect(client.webhooks.inactivate['is_active']).to be(false) if original
      end
    ensure
      if original
        # Restore the original subscription (events + active state).
        cleanup_resources(
          ['webhook subscription', lambda {
            client.webhooks.register(
              url: original['url'], email: original['email'],
              events: original['events'], is_active: original['is_active']
            )
          }]
        )
      end
    end
  end

  it 'creates, reads and lists a template via multipart upload' do
    id = nil
    document_id = nil
    created_signer_id = nil

    begin
      source = { buffer: sample_pdf('Template'), file_name: "sdk-live-#{rand(9999)}.pdf" }
      template = client.templates.create(source)
      id = template['id']
      details = wait_for_template_ready(client, id)
      renamed = client.templates.update(id, name: "sdk-live-template-#{rand(9999)}")
      page_id = details.fetch('pages').first.fetch('id')
      signer_id, signer_created = find_or_create_signer(client, 'SDK Template Signer', primary_email)
      created_signer_id = signer_id if signer_created
      role_id = details.fetch('roles').first.fetch('id')
      role_signer = { role_id: role_id, id: signer_id }
      estimate = client.documents.estimate_cost_from_template(id, [{ role_id: role_id }])
      created_document = client.documents.create_from_template(id, [role_signer])
      document_id = created_document['id']
      client.documents.wait_until_ready(document_id, max_wait_seconds: 60)

      aggregate_failures do
        expect(template['resource']).to eq('template')
        expect(template['roles']).to be_an(Array)
        expect(details['id']).to eq(id)
        expect(renamed['id']).to eq(id)
        expect(client.templates.list(per_page: 5)[:data]).to be_an(Array)
        expect(client.templates.download_page(id, page_id).bytesize).to be > 0
        expect(estimate).to include('has_sufficient_resources')
        expect(created_document['id']).to be_a(String)
      end
    ensure
      cleanup_resources(
        ['template document', -> { delete_document_when_ready(client, document_id) if document_id }],
        ['template', -> { delete_template_when_ready(client, id) if id }],
        ['signer', -> { client.signers.delete(created_signer_id) if created_signer_id }]
      )
    end
  end

  it 'reads and safely round-trips notification preferences' do
    preference = 'DocumentCompleted'
    original_value = nil

    begin
      original_value = client.users.notification_preferences.fetch(preference)
      expect(original_value).to be(true).or be(false)

      updated = client.users.update_notification_preferences(preference => original_value)
      expect(updated.fetch(preference)).to eq(original_value)
    rescue Assinafy::ApiError => e
      raise unless e.status_code == 404

      skip 'notification preferences are not enabled in this sandbox'
    ensure
      cleanup_resources(
        ['notification preferences', lambda {
          client.users.update_notification_preferences(preference => original_value) unless original_value.nil?
        }]
      )
    end
  end

  it 'reads document statuses and verifies an unknown signature hash' do
    aggregate_failures do
      expect(client.documents.statuses.map { |s| s['code'] }).to include('metadata_ready')
      expect(client.documents.verify('INVALIDHASHEXAMPLE')).to include('is_valid' => false)
    end
  end
end
