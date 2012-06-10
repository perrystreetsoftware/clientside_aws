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

require 'clientside_aws/dynamodb'
require 'clientside_aws/sqs'

configure :test do
  AWS_REDIS = Redis.new(:host => "localhost", :port => 6380, :timeout => 10)
end

configure :development do
  AWS_REDIS = Redis.new
end

DYNAMODB_PREFIX = "DynamoDBv20110924"

get '/' do
  "hello"
end
