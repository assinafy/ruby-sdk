# frozen_string_literal: true

# `sig/assinafy.rbs` ships inside the gem, so consumers type-check against it.
# Steep no longer verifies it on every build, which left nothing stopping a new
# public method from shipping without a signature. This is that guard: it does
# not type-check, it only asserts the published surface and the signature file
# describe the same methods.
RSpec.describe 'sig/assinafy.rbs', type: :signatures do # rubocop:disable RSpec/DescribeClass
  let(:signatures) { File.read(File.expand_path('../sig/assinafy.rbs', __dir__)) }

  # Every name the RBS block for `class`/`module <Name>` exposes as a method:
  # `def name:`, `def self.name:`, and the `attr_reader`s the Client uses for
  # its resource accessors.
  def declared_methods(name)
    body = signatures[/^\s*(?:class|module) #{Regexp.escape(name)}\b.*?^\s*end$/m].to_s

    body.scan(/^\s*(?:def (?:self\.)?|attr_reader |attr_accessor )([a-z_][A-Za-z0-9_]*[?!]?):/)
        .flatten.map(&:to_sym)
  end

  def resource_classes
    Assinafy::Resources.constants.map(&:to_s).reject { |name| name == 'BaseResource' }.sort
  end

  it 'declares every resource class the SDK exposes' do
    aggregate_failures do
      resource_classes.each do |class_name|
        expect(signatures).to include("class #{class_name} < BaseResource"),
                              "sig/assinafy.rbs is missing class #{class_name}"
      end
    end
  end

  it 'declares a signature for every public resource method' do
    aggregate_failures do
      resource_classes.each do |class_name|
        klass   = Assinafy::Resources.const_get(class_name)
        missing = klass.public_instance_methods(false).sort - declared_methods(class_name)

        expect(missing).to be_empty,
                           "sig/assinafy.rbs is missing #{class_name}##{missing.join(', #')}"
      end
    end
  end

  it 'declares a signature for every public Client method' do
    missing = (Assinafy::Client.public_instance_methods(false) - Object.instance_methods).sort -
              declared_methods('Client')

    expect(missing).to be_empty, "sig/assinafy.rbs is missing Client##{missing.join(', #')}"
  end

  it 'declares a signature for every public Assinafy::OAuth helper' do
    missing = Assinafy::OAuth.singleton_methods(false).sort - declared_methods('OAuth')

    expect(missing).to be_empty, "sig/assinafy.rbs is missing Assinafy::OAuth.#{missing.join(', .')}"
  end

  it 'declares the error classes the SDK raises' do
    aggregate_failures do
      %w[Error ApiError ValidationError OAuthError NetworkError].each do |class_name|
        expect(signatures).to match(/^\s*class #{class_name}\b/),
                              "sig/assinafy.rbs is missing error class #{class_name}"
      end
    end
  end
end
