require_relative 'clientside_aws/mock/core'
require_relative 'clientside_aws/mock/s3'
# require_relative 'clientside_aws/mock/ses'
# require_relative 'clientside_aws/mock/sns'
# require_relative 'clientside_aws/mock/kinesis'
require 'httparty'
require 'webmock/rspec'
WebMock.allow_net_connect!

# WebMock.before_request do |request_signature, response|
#   puts "Request #{request_signature} was made and #{response} was returned"
#   binding.pry
# end

def mock_uri(uri:)
  uri.scheme = 'http'
  uri.path = uri.host + uri.path
  uri.host = 'aws'
  uri.port = '4567'

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

WebMock.stub_request(:post, %r{https\:\/\/[\w\.]+\.us\-mockregion\-1}) \
       .to_return do |request|
  mock_post(request: request)
end

WebMock.stub_request(:get, %r{https\:\/\/[\w\.]+\.us\-mockregion\-1}) \
       .to_return do |request|
  mock_get(request: request)
end

WebMock.stub_request(:head, %r{https\:\/\/[\w\.]+\.us\-mockregion\-1}) \
       .to_return do |request|
  mock_head(request: request)
end

WebMock.stub_request(:put, %r{https\:\/\/[\w\.]+\.us\-mockregion\-1}) \
       .to_return do |request|
  mock_put(request: request)
end

WebMock.stub_request(:delete, %r{https\:\/\/[\w\.]+\.us\-mockregion\-1}) \
       .to_return do |request|
  mock_delete(request: request)
end

RSpec.configure do |config|
  config.before(:each) do
    stub_request(:post, %r{https\:\/\/([\w\.]+\.us\-mockregion\-1|aws)}) \
      .to_return do |request|
      mock_post(request: request)
    end
    stub_request(:get, %r{https\:\/\/([\w\.]+\.us\-mockregion\-1|aws)}) \
      .to_return do |request|
      mock_get(request: request)
    end
    stub_request(:head, %r{https\:\/\/[\w\.]+\.us\-mockregion\-1}) \
      .to_return do |request|
      mock_head(request: request)
    end
    stub_request(:put, %r{https\:\/\/[\w\.]+\.us\-mockregion\-1}) \
      .to_return do |request|
      mock_put(request: request)
    end
    stub_request(:delete, %r{https\:\/\/[\w\.]+\.us\-mockregion\-1}) \
      .to_return do |request|
      mock_delete(request: request)
    end
  end
end
