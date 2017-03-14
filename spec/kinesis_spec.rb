
$LOAD_PATH << "#{File.dirname(__FILE__)}/../"

require 'aws-sdk'
require 'aws-sdk-v1'
require 'spec/spec_helper'

describe 'Profiles Spec' do
  include Rack::Test::Methods
  def app
    Sinatra::Application
  end

  it 'v1: should post to Kinesis okay' do
    AWS::Kinesis::Client.new.put_record(stream_name: 'foo',
                                        data: { bar: 1 }.to_json,
                                        partition_key: 1.to_s)
  end

  it 'v2: should post to Kinesis okay' do
    Aws::Kinesis::Client.new.put_record(stream_name: 'foo',
                                        data: { bar: 1 }.to_json,
                                        partition_key: 1.to_s)
  end
end
