# frozen_string_literal: true

# End-to-end integration specs that exercise the SDK against the real Assinafy
# sandbox. They are excluded from the default suite and only run when:
#
#   ASSINAFY_LIVE=1 \
#   ASSINAFY_API_KEY=... \
#   ASSINAFY_ACCOUNT_ID=... \
#   ASSINAFY_BASE_URL=https://sandbox.assinafy.com.br/v1 \
#   bundle exec rspec spec/integration
#
# They create and clean up real resources, and (for the assignment flow) send
# real signature-request emails to ASSINAFY_TEST_EMAIL / ASSINAFY_TEST_EMAIL2.
RSpec.describe 'Assinafy live sandbox', :live do # rubocop:disable RSpec/DescribeClass
  def build_client
    Assinafy::Client.create(
      ENV.fetch('ASSINAFY_API_KEY'),
      ENV.fetch('ASSINAFY_ACCOUNT_ID'),
      base_url: ENV.fetch('ASSINAFY_BASE_URL', 'https://sandbox.assinafy.com.br/v1')
    )
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
    return existing['id'] if existing

    client.signers.create(full_name: full_name, email: email)['id']
  end

  let(:client)          { build_client }
  let(:primary_email)   { ENV.fetch('ASSINAFY_TEST_EMAIL', 'bill@febacapital.com') }
  let(:secondary_email) { ENV.fetch('ASSINAFY_TEST_EMAIL2', 'billm@billm.org') }

  it 'fetches the authenticated user profile' do
    me = client.users.me
    expect(me['user']).to include('email')
    expect(me['accounts']).to be_an(Array)
  end

  it 'lists accounts, reads the current account and its theme' do
    aggregate_failures do
      expect(client.accounts.list[:data]).to be_an(Array)
      expect(client.accounts.get).to include('id' => ENV.fetch('ASSINAFY_ACCOUNT_ID'))
      expect(client.accounts.theme).to include('account_name')
    end
  end

  it 'runs the full account + logo lifecycle on a throwaway account' do
    acc = client.accounts.create(name: "sdk-live-#{rand(1_000_000)}")
    id  = acc['id']
    expect(id).to be_a(String)

    upload = client.accounts.upload_logo({ buffer: sample_png, file_name: 'logo.png' }, id)
    expect(upload).to include('mime_type')
    expect(client.accounts.download_logo(id).bytesize).to be > 0
    expect(client.accounts.update({ name: 'sdk-live-renamed' }, id)['name']).to eq('sdk-live-renamed')

    expect(client.accounts.delete_logo(id)).to be_nil
    expect(client.accounts.delete(force: true, account_id_override: id)).to be_nil
  end

  it 'runs the document + assignment lifecycle (sends real emails)' do
    doc = client.documents.upload({ buffer: sample_pdf, file_name: "sdk-live-#{rand(1_000_000)}.pdf" })
    id  = doc['id']

    begin
      ready = client.documents.wait_until_ready(id, max_wait_seconds: 30)
      renamed = client.documents.rename(id, 'sdk-live-renamed.pdf')

      s1 = find_or_create_signer(client, 'Audit Bill', primary_email)
      s2 = find_or_create_signer(client, 'Audit Bill M', secondary_email)

      estimate = client.assignments.estimate_cost(id, signers: [{ id: s1 }, { id: s2 }])
      assignment = client.assignments.create(
        id, signers: [{ id: s1 }, { id: s2 }], message: 'SDK live integration - please ignore'
      )
      aid = assignment['id']

      aggregate_failures do
        expect(ready['status']).to eq('metadata_ready').or eq('pending_signature')
        expect(renamed['name']).to eq('sdk-live-renamed.pdf')
        expect(estimate).to include('has_sufficient_resources')
        expect(assignment['signers'].size).to eq(2)
        expect(assignment['signing_urls']).to be_an(Array)

        expect(client.documents.details(id)['id']).to eq(id)
        expect(client.documents.search('sdk-live')[:data]).to be_an(Array)
        expect(client.documents.activities(id)).to be_an(Array)
        expect(client.documents.thumbnail(id).bytesize).to be > 0
        expect(client.documents.download(id, 'original').byteslice(0, 4)).to eq('%PDF')
        expect(client.documents.list(per_page: 3)[:meta]).to include(:current_page)
        expect(client.assignments.list[:data].map { |a| a['id'] }).to include(aid)
        expect(client.assignments.whatsapp_notifications(id, aid)).to be_an(Array)
        expect(client.assignments.reset_expiration(id, aid, nil)['id']).to eq(aid)
        expect(client.assignments.estimate_resend_cost(id, aid, s1)).to include('has_sufficient_credits')
        expect(client.assignments.resend_notification(id, aid, s1)).to include('is_sent' => true)
      end
    ensure
      client.documents.delete(id)
    end
  end

  it 'runs the signer workspace CRUD lifecycle' do
    email = "sdk-live-#{rand(1_000_000)}@billm.org"
    created = client.signers.create(full_name: 'SDK Live', email: email)
    id = created['id']

    begin
      aggregate_failures do
        expect(client.signers.get(id)['email']).to eq(email)
        expect(client.signers.update(id, full_name: 'SDK Live Renamed')['full_name']).to eq('SDK Live Renamed')
        expect(client.signers.list(per_page: 1)[:data]).to be_an(Array)
        expect(client.signers.find_by_email(email)['id']).to eq(id)
      end
    ensure
      client.signers.delete(id)
    end
  end

  it 'runs the field definition + validation lifecycle' do
    field = client.fields.create(name: "SDK Live CPF #{rand(9999)}", type: 'cpf')
    id = field['id']

    begin
      aggregate_failures do
        expect(client.fields.get(id)['type']).to eq('cpf')
        expect(client.fields.update(id, name: 'SDK Live Renamed')['name']).to eq('SDK Live Renamed')
        expect(client.fields.validate(id, '400.676.228-36')).to include('success')
        multi = client.fields.validate_multiple([{ field_id: id, value: '11144477735' }])
        expect(multi.first).to include('field_id' => id)
        expect(client.fields.list[:data]).to be_an(Array)
        expect(client.fields.types).to be_an(Array)
      end
    ensure
      client.fields.delete(id)
    end
  end

  it 'runs the tag lifecycle and document attach/detach' do
    tag = client.tags.create(name: "sdk-live-#{rand(1_000_000)}", color: 'ff8800')
    tag_id = tag['id']
    doc = client.documents.upload({ buffer: sample_pdf, file_name: "sdk-tag-#{rand(9999)}.pdf" })
    doc_id = doc['id']
    client.documents.wait_until_ready(doc_id, max_wait_seconds: 30)

    begin
      aggregate_failures do
        expect(client.tags.list[:data]).to be_an(Array)
        expect(client.tags.update(tag_id, name: "#{tag['name']}-renamed")['name']).to end_with('-renamed')
        expect(client.documents.append_tags(doc_id, ["#{tag['name']}-renamed"])).to be_an(Array)
        expect(client.documents.list_tags(doc_id)).to be_an(Array)
        expect(client.documents.detach_tag(doc_id, tag_id)).to include('detached' => true)
      end
    ensure
      client.documents.delete(doc_id)
      client.tags.delete(tag_id)
    end
  end

  it 'reads webhook subscription, dispatches and event types; toggles active state' do
    original = client.webhooks.get
    skip 'no webhook subscription configured on this account' unless original

    begin
      aggregate_failures do
        expect(client.webhooks.list_event_types).to be_an(Array)
        expect(client.webhooks.list_dispatches(per_page: 2)[:data]).to be_an(Array)
        expect(client.webhooks.inactivate['is_active']).to be(false)
      end
    ensure
      # Restore the original subscription (events + active state).
      client.webhooks.register(
        url: original['url'], email: original['email'],
        events: original['events'], is_active: original['is_active']
      )
    end
  end

  it 'creates, reads and lists a template via multipart upload' do
    template = client.templates.create({ buffer: sample_pdf('Template'), file_name: "sdk-live-#{rand(9999)}.pdf" })
    id = template['id']

    aggregate_failures do
      expect(template['resource']).to eq('template')
      expect(template['roles']).to be_an(Array)
      expect(client.templates.get(id)['id']).to eq(id)
      expect(client.templates.list(per_page: 5)[:data]).to be_an(Array)
    end
    # NOTE: templates cannot be deleted while status is "Processing"; the sandbox
    # reaps them, so no cleanup is attempted here.
  end

  it 'reads document statuses and verifies an unknown signature hash' do
    aggregate_failures do
      expect(client.documents.statuses.map { |s| s['code'] }).to include('metadata_ready')
      expect(client.documents.verify('INVALIDHASHEXAMPLE')).to include('is_valid' => false)
    end
  end
end
