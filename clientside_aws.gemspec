# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'clientside_aws/version'

Gem::Specification.new do |spec|
  spec.name          = "clientside_aws"
  spec.version       = ClientsideAws::VERSION
  spec.authors       = ["Perry Street Software, Inc."]
  spec.email         = ["noreply@scruff.com"]
  spec.description   = "This code is meant to be used by developers who are attempting to build web applications on AWS but wish to run client-side testing and validation."
  spec.summary       = "Select AWS Services Replicated on Your Client"
  spec.homepage      = "https://github.com/perrystreetsoftware/clientside_aws"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

# spec.add_development_dependency "rake", "10.1.0"
  spec.add_development_dependency 'rack-test', '0.5.7'
  spec.add_development_dependency 'rspec', '2.14.1'
  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_dependency 'aws-sdk', '1.59.0'
  spec.add_dependency 'builder', '3.1.4'
  spec.add_dependency 'httparty', '0.11.0'
  spec.add_dependency 'macaddr', '1.6.7'
  spec.add_dependency 'mini_portile', '0.5.2'
  spec.add_dependency 'monkey-lib', '0.5.4'
  spec.add_dependency 'nokogiri', '1.6.1'
  spec.add_dependency 'rack-cors', '0.2.9'
  spec.add_dependency 'rack', '1.5.2'
  spec.add_dependency 'redis', '3.0.1'
  spec.add_dependency 'sinatra-reloader', '0.5.0'
  spec.add_dependency 'sinatra-sugar', '0.5.1'
  spec.add_dependency 'sinatra', '1.4.2'
  spec.add_dependency 'uuid', '2.3.1'
  spec.add_dependency 'uuidtools', '2.1.4'
  spec.add_dependency 'backports', '3.6.3'
  spec.add_dependency 'rack-protection', '1.5.3'
  spec.add_dependency 'sinatra-advanced-routes', '0.5.3'
  spec.add_dependency 'multi_json', '1.10.1'
  spec.add_dependency 'multi_xml', '0.5.3'
  spec.add_dependency 'tilt', '1.3.6'
  spec.add_dependency 'systemu', '2.6.4'
end
