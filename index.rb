$LOAD_PATH << "#{File.dirname(__FILE__)}/"

require 'rubygems'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'json'
require 'redis'
require 'bigdecimal'
require 'builder'
require 'digest'
require 'uuid'
require 'base64'
require 'rack'
require 'rack/cors'
require 'rack/protection'

ENV['RACK_ENV'] = "development" unless ENV['RACK_ENV']

require 'clientside_aws/core'
require 'clientside_aws/dynamodb'
require 'clientside_aws/sqs'
require 'clientside_aws/s3'
require 'clientside_aws/ses'
require 'clientside_aws/elastic_transcoder'
require 'clientside_aws/sns'
require 'clientside_aws/kinesis'

# puts "invoking #{AWS::Core.testing ? 'test' : 'dev'}"
options = { host: 'localhost', port: 6380, timeout: 10 }
options = { host: 'redis' } unless AWS::Core.testing
AWS_REDIS = Redis.new(options)

configure :development do
  use Rack::Cors do
    allow do
      origins '*'
      resource '*', :headers => :any, :methods => [:get, :post, :options, :put]
    end
  end
  set :protection, :except => [:http_origin]
end

DYNAMODB_PREFIX = "DynamoDBv20110924"

get '/' do
  "hello"
end
