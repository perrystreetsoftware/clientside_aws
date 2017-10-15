# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'clientside_aws/version'

Gem::Specification.new do |spec|
  spec.name          = 'clientside_aws'
  spec.version       = ClientsideAws::VERSION
  spec.authors       = ['Perry Street Software, Inc.']
  spec.email         = ['noreply@scruff.com']
  spec.description   = 'This code is meant to be used by developers who are attempting to build web applications on AWS but wish to run client-side testing and validation.'
  spec.summary       = 'Select AWS Services Replicated on Your Client'
  spec.homepage      = 'https://github.com/perrystreetsoftware/clientside_aws'
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  spec.executables   = %w[clientside_aws_build clientside_aws_run]
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'rake', '10.1.0'
  spec.add_development_dependency 'rack-test', '0.5.7'
  spec.add_development_dependency 'rspec', '2.14.1'
  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_dependency 'aws-sdk-v1', '1.66.0'
  spec.add_dependency 'aws-sdk', '~> 2.0'
  spec.add_dependency 'builder', '~> 3.1'
  spec.add_dependency 'httparty', '~> 0.15'
  spec.add_dependency 'json', '~> 1.8'
  spec.add_dependency 'webmock', '~> 3.1'
end
