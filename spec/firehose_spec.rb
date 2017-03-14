
$LOAD_PATH << "#{File.dirname(__FILE__)}/../"

require 'aws-sdk'
require 'aws-sdk-v1'
require 'spec/spec_helper'

describe 'Profiles Spec' do
  include Rack::Test::Methods
  def app
    Sinatra::Application
  end

  it 'should post to Firehose okay' do
    firehose = Aws::Firehose::Client.new
    firehose.put_record_batch(delivery_stream_name: 'test',
                              records: [{ data: 'foo' }, { data: 'bar' }])
  end
end
