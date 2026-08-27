# frozen_string_literal: true

D = Steep::Diagnostic

target :assinafy do
  signature 'sig'
  signature 'typecheck'
  check 'lib'

  library 'json'
  library 'openssl'
  library 'stringio'
  library 'uri'

  configure_code_diagnostics(D::Ruby.strict) do |diagnostics|
    diagnostics[D::Ruby::UnannotatedEmptyCollection] = nil
  end
end
