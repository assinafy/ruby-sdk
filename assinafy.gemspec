# frozen_string_literal: true

require_relative 'lib/assinafy/version'

Gem::Specification.new do |spec|
  spec.name    = 'assinafy'
  spec.version = Assinafy::VERSION
  spec.authors = ['Assinafy SDK Contributors']
  spec.email   = ['sdk@assinafy.com.br']

  spec.summary     = 'Ruby SDK for the Assinafy digital signature API'
  spec.description = 'Ruby SDK for Assinafy. Covers the documented authentication, ' \
                     'document, signer, assignment, webhook, template, and field APIs, plus the high-level ' \
                     'upload_and_request_signatures helper.'
  spec.homepage    = 'https://github.com/assinafy/ruby-sdk'
  spec.license     = 'MIT'

  spec.required_ruby_version = '>= 2.7'

  spec.metadata['source_code_uri']   = 'https://github.com/assinafy/ruby-sdk'
  spec.metadata['changelog_uri']     = 'https://github.com/assinafy/ruby-sdk/blob/main/CHANGELOG.md'
  spec.metadata['documentation_uri'] = 'https://api.assinafy.com.br/v1/docs'

  spec.files         = Dir['lib/**/*.rb', 'CHANGELOG.md', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'faraday', '>= 1.10', '< 3.0'
  spec.add_dependency 'faraday-multipart', '>= 1.0', '< 2.0'

  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'webmock', '~> 3.0'
end
