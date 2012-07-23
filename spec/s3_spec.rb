require 'spec/spec_helper'
require 'aws-sdk'
require 'aws_mock'

describe 'Profiles Spec' do
  include Rack::Test::Methods
  def app
    Sinatra::Application
  end
  # adding in for ability to access via other 'examples'
  
  it "says hello" do
    get '/'
    last_response.should be_ok
  end
  
  it "should post to S3 okay" do
    s3 = AWS::S3.new(
      :access_key_id => "...",
      :secret_access_key => "...")   
    s3.buckets.create('test')
    bucket = s3.buckets[:test]
    bucket.exists?
    object = bucket.objects['test.file']

    initial_hash = Digest::MD5.hexdigest(File.read("#{File.dirname(__FILE__)}/../public/images/spacer.gif"))
    object.write(:file => "#{File.dirname(__FILE__)}/../public/images/spacer.gif")
    Digest::MD5.hexdigest(object.read()).should == initial_hash
    object.exists?.should == true

    bucket.objects['asdfdsfasdf'].exists?.should == false

    object.delete()
    object.exists?.should == false
    
    json_value = {:foo => "bar"}.to_json
    object = bucket.objects['test.json']
    object.write(json_value, :content_type => "application/json")
    object.read().should == json_value
    object.content_type.should == "application/json"
  end  
end