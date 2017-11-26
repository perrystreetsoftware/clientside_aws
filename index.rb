$LOAD_PATH << "#{File.dirname(__FILE__)}/"

require 'rubygems'
require 'sinatra'
require 'json'
require 'redis'
require 'bigdecimal'
require 'builder'
require 'digest'
require 'base64'
require 'rack'
require 'rack/cors'
require 'rack/protection'
require 'aws-sdk'

ENV['RACK_ENV'] = 'development' unless ENV['RACK_ENV']

require 'clientside_aws/mock/core'

require 'clientside_aws/dynamodb'
require 'clientside_aws/sqs'
require 'clientside_aws/s3'
require 'clientside_aws/ec2'
require 'clientside_aws/ses'
require 'clientside_aws/elastic_transcoder'
require 'clientside_aws/sns'
require 'clientside_aws/kinesis'
require 'clientside_aws/firehose'

options = if defined?(Sinatra::Base.settings.clientside_aws_testing) && \
             Sinatra::Base.settings.clientside_aws_testing
            { host: 'localhost', port: 6380, timeout: 10 }
          elsif ENV.key?('REDIS_HOST') && ENV.key?('REDIS_PORT')
            { host: ENV['REDIS_HOST'],
              port: ENV['REDIS_PORT'].to_i }
          else
            # Use localhost port 6379
            {}
          end

AWS_REDIS = Redis.new(options)

configure :development do
  use Rack::Cors do
    allow do
      origins '*'
      resource '*', headers: :any, methods: [:get, :post, :options, :put]
    end
  end
  set :protection, except: [:http_origin]
end

DYNAMODB_PREFIX = 'DynamoDBv20110924'.freeze

S3_CONFIG = {
  region: 'us-mockregion-1',
  access_key_id: '...',
  secret_access_key: '...',
  force_path_style: true,
  endpoint: 'http://app_rspec_localstack:4572'
}.freeze

get '/' do
  'hello'
end
