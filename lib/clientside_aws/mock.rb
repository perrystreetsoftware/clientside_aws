# frozen_string_literal: true

# Include this file in separate projects when you want to redirect
# requests that normally would go to the AWS production infrastrure and
# instead route them to a container you are running locally

require_relative '../../clientside_aws/mock/core'
require_relative '../../clientside_aws/mock/s3'
require_relative '../../clientside_aws/mock/ses'
require_relative '../../clientside_aws/mock/sns'
require_relative '../../clientside_aws/mock/kinesis'
require_relative '../../clientside_aws/mock/firehose'

require 'httparty'
# We do NOT use webmock/rspec because it removes the matchers after every test
# this breaks MET which is expecting to be able to communicate with AWS
# in the before(:all) rspec block
# Thus we just manually include what we needed from webmock/rspec and
# did not include the code to remove matchers after every test
require 'webmock'
require 'rspec'

WebMock.enable!
WebMock.allow_net_connect!

# WebMock.before_request do |request_signature, response|
#   puts "Request #{request_signature} was made and #{response} was returned"
#   binding.pry
# end

# Helper methods used to mock requests from code (either in development or test)
# to our container -- thus requiring HTTParty
def mock_uri(uri:)
  uri.scheme = 'http'
  uri.path = uri.host + uri.path
  uri.host = ClientsideAws.configuration.host
  uri.port = ClientsideAws.configuration.port

  uri
end

def mock_post(request:)
  response = HTTParty.post(mock_uri(uri: request.uri),
                           body: request.body,
                           headers: \
                            request.headers.merge('SERVER_NAME' => \
                                                  request.uri.host))

  { headers: response.headers,
    status: response.code,
    body: response.body }
end

def mock_get(request:)
  response = HTTParty.get(mock_uri(uri: request.uri),
                          query: request.uri.query_values,
                          headers: \
                            request.headers.merge('SERVER_NAME' => \
                                                  request.uri.host))

  { headers: response.headers,
    status: response.code,
    body: response.body }
end

def mock_head(request:)
  response = HTTParty.get(mock_uri(uri: request.uri),
                          query: request.uri.query_values,
                          headers: \
                            request.headers.merge('SERVER_NAME' => \
                                                  request.uri.host))

  { headers: response.headers,
    status: response.code,
    body: '' }
end

def mock_put(request:)
  response = HTTParty.put(mock_uri(uri: request.uri),
                          body: request.body,
                          headers: \
                            request.headers.merge('SERVER_NAME' => \
                                                  request.uri.host))

  { headers: response.headers,
    status: response.code,
    body: response.body }
end

def mock_delete(request:)
  response = HTTParty.delete(mock_uri(uri: request.uri),
                             query: request.uri.query_values,
                             headers: \
                               request.headers.merge('SERVER_NAME' => \
                                                     request.uri.host))

  { headers: response.headers,
    status: response.code,
    body: response.body }
end

# Use WebMock to intercept all requests and redirect to our container
WebMock.stub_request(:post, %r{https?\:\/\/[\w\.]+\.us\-mockregion\-1}) \
       .to_return do |request|
  mock_post(request: request)
end

WebMock.stub_request(:get, %r{https?\:\/\/[\w\.]+\.us\-mockregion\-1}) \
       .to_return do |request|
  mock_get(request: request)
end

WebMock.stub_request(:head, %r{https?\:\/\/[\w\.]+\.us\-mockregion\-1}) \
       .to_return do |request|
  mock_head(request: request)
end

WebMock.stub_request(:put, %r{https?\:\/\/[\w\.]+\.us\-mockregion\-1}) \
       .to_return do |request|
  mock_put(request: request)
end

WebMock.stub_request(:delete, %r{https?\:\/\/[\w\.]+\.us\-mockregion\-1}) \
       .to_return do |request|
  mock_delete(request: request)
end

#
# Testing configuration
#
# In this case, we need to determine if we are running our own tests,
# in which case we use the rack/test request methods; otherwise use HTTParty
# to hit a separate test docker container
#

RSpec.configure do |config|
  config.include WebMock::API
  config.include WebMock::Matchers

  config.before(:each) do
    WebMock.reset!

    clientside_aws_testing = \
      defined?(Sinatra::Base.settings.clientside_aws_testing) && \
      Sinatra::Base.settings.clientside_aws_testing

    if clientside_aws_testing
      # We are testing our own stuff; use rack/test methods
      stub_request(:post, /us-mockregion-1/).to_return do |request|
        post "/#{request.uri.host}",
             request.body,
             request.headers.merge('SERVER_NAME' => request.uri.host)

        { headers: last_response.header,
          status: last_response.status,
          body: last_response.body }
      end

      stub_request(:get, /us-mockregion-1/).to_return do |request|
        get "/#{request.uri.host}#{request.uri.path}",
            request.uri.query_values,
            request.headers.merge('SERVER_NAME' => request.uri.host)

        { headers: last_response.header,
          status: last_response.status,
          body: last_response.body }
      end

      stub_request(:put, /us-mockregion-1/).to_return do |request|
        put "/#{request.uri.host}#{request.uri.path}",
            { body: request.body },
            request.headers.merge('SERVER_NAME' => request.uri.host)

        { headers: last_response.header,
          status: last_response.status,
          body: last_response.body }
      end

      stub_request(:head, /us-mockregion-1/).to_return do |request|
        get "/#{request.uri.host}#{request.uri.path}",
            { head_request: 1 }.merge(request.uri.query_values || {}),
            request.headers.merge('SERVER_NAME' => request.uri.host)

        { headers: last_response.header,
          status: last_response.status,
          body: '' }
      end

      stub_request(:delete, /us-mockregion-1/).to_return do |request|
        delete "/#{request.uri.host}#{request.uri.path}",
               request.uri.query_values,
               request.headers.merge('SERVER_NAME' => request.uri.host)

        { headers: last_response.header,
          status: last_response.status,
          body: last_response.body }
      end
    else
      # A third-party has included us as a gem and is testing his own
      # code; assume we have a test clientside_aws docker container
      # running and hit that with HTTParty
      stub_request(:post, %r{https?\:\/\/[\w\.]+\.us\-mockregion\-1}) \
        .to_return do |request|
        mock_post(request: request)
      end
      stub_request(:get, %r{https?\:\/\/[\w\.]+\.us\-mockregion\-1}) \
        .to_return do |request|
        mock_get(request: request)
      end
      stub_request(:head, %r{https?\:\/\/[\w\.]+\.us\-mockregion\-1}) \
        .to_return do |request|
        mock_head(request: request)
      end
      stub_request(:put, %r{https?\:\/\/[\w\.]+\.us\-mockregion\-1}) \
        .to_return do |request|
        mock_put(request: request)
      end
      stub_request(:delete, %r{https?\:\/\/[\w\.]+\.us\-mockregion\-1}) \
        .to_return do |request|
        mock_delete(request: request)
      end
    end
  end
end
