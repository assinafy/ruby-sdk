# frozen_string_literal: true

require 'digest'
require 'json'
require 'net/http'
require 'uri'

require_relative '../lib/assinafy/version'

module AssinafyApiContract
  SOURCE = URI('https://api.assinafy.com.br/v1/docs/openapi.json')
  EXPECTED_PATH = File.expand_path('../spec/fixtures/api_contract.json', __dir__)
  HTTP_METHODS = %w[get put post delete options head patch trace].freeze
  COMPARED_KEYS = %w[
    openapi api_version path_count operation_count schema_count
    canonical_sha256 operations schemas
  ].freeze
  MAX_RESPONSE_BYTES = 5 * 1024 * 1024

  module_function

  def canonical(value)
    case value
    when Hash
      value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
    when Array
      value.map { |item| canonical(item) }
    else
      value
    end
  end

  def snapshot(document)
    paths = document.fetch('paths')
    schemas = document.dig('components', 'schemas') || {}
    operations = paths.flat_map do |path, path_item|
      path_item.keys.filter_map do |method|
        "#{method.upcase} #{path}" if HTTP_METHODS.include?(method)
      end
    end.sort

    {
      'openapi'          => document.fetch('openapi'),
      'api_version'      => document.dig('info', 'version'),
      'path_count'       => paths.length,
      'operation_count'  => operations.length,
      'schema_count'     => schemas.length,
      'canonical_sha256' => Digest::SHA256.hexdigest(JSON.generate(canonical(document))),
      'operations'       => operations,
      'schemas'          => schemas.keys.sort
    }
  end

  def fetch_remote
    Net::HTTP.start(SOURCE.host, SOURCE.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      request = Net::HTTP::Get.new(SOURCE)
      request['Accept'] = 'application/json'
      request['User-Agent'] = Assinafy::USER_AGENT
      response = http.request(request)
      raise "upstream returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      raise 'upstream document exceeds size limit' if response.body.bytesize > MAX_RESPONSE_BYTES

      response.body
    end
  end

  def source_body(arguments)
    return fetch_remote if arguments.empty?

    unless arguments.length == 2 && arguments.first == '--file'
      raise ArgumentError.new('usage: check_api_contract.rb [--file OPENAPI_JSON]')
    end

    File.binread(arguments.last)
  end

  def differences(expected, actual)
    COMPARED_KEYS.filter_map do |key|
      next if expected[key] == actual[key]

      "#{key}: expected #{expected[key].inspect}, got #{actual[key].inspect}"
    end
  end

  def print_set_changes(label, expected, actual, error_output)
    added = actual - expected
    removed = expected - actual
    error_output.puts("Added #{label}: #{added.join(', ')}") unless added.empty?
    error_output.puts("Removed #{label}: #{removed.join(', ')}") unless removed.empty?
  end

  def run(arguments, output: $stdout, error_output: $stderr)
    expected = JSON.parse(File.binread(EXPECTED_PATH))
    actual = snapshot(JSON.parse(source_body(arguments)))
    changes = differences(expected, actual)

    if changes.empty?
      output.puts("Assinafy API contract matches the expected contract (#{actual['operation_count']} operations, " \
                  "#{actual['schema_count']} schemas).")
      return 0
    end

    error_output.puts('Assinafy API contract compatibility change detected:')
    changes.each { |change| error_output.puts("- #{change}") unless change.start_with?('operations:', 'schemas:') }
    print_set_changes('operations', expected.fetch('operations'), actual.fetch('operations'), error_output)
    print_set_changes('schemas', expected.fetch('schemas'), actual.fetch('schemas'), error_output)
    1
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    exit AssinafyApiContract.run(ARGV)
  rescue StandardError => e
    warn "Contract check failed: #{e.class}: #{e.message}"
    exit 2
  end
end
