require_relative 'clientside_aws/core'
require 'webmock/rspec'
WebMock.disable_net_connect!(allow_localhost: true)

# WebMock.before_request do |request_signature, response|
#   puts "Request #{request_signature} was made and #{response} was returned"
#   binding.pry
# end

module AWS
  class S3
    class Bucket
      begin
        old_exists = instance_method(:exists?)
        define_method(:exists?) do
          begin
            old_exists.bind(self).call
          rescue Errors::NoSuchKey
            false # bucket does not exist
          end
        end
      rescue NameError
        # aws-sdk-v1 is not being used
      end
    end
  end
end

RSpec.configure do |config|
  config.before(:each) do
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
  end
end
