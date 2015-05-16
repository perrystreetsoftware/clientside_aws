$LOAD_PATH << "#{File.dirname(__FILE__)}/../"

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
    expect(last_response.ok?).to be true
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
    expect(Digest::MD5.hexdigest(object.read())).to eq initial_hash
    expect(object.exists?).to be true

    expect(bucket.objects['asdfdsfasdf'].exists?).to be false

    object.delete()
    expect(object.exists?).to be false
    
    json_value = {:foo => "bar"}.to_json
    object = bucket.objects['test.json']
    object.write(json_value, :content_type => "application/json")
    expect(object.read()).to eq json_value
    expect(object.content_type).to eq "application/json"
    expect(object.etag).to eq Digest::MD5.hexdigest(json_value)
  end
  
  it "should support subpaths" do
    s3 = AWS::S3.new(
      :access_key_id => "...",
      :secret_access_key => "...")
    s3.buckets.create('test')
    bucket = s3.buckets[:test]
    expect(bucket.exists?).to be true
    object = bucket.objects['foo/bar/test.file']

    object.write(:file => "#{File.dirname(__FILE__)}/../public/images/spacer.gif")
    expect(object.exists?).to be true
    
    get '/s3/test/foo/bar/test.file'
    expect(last_response.ok?).to be true
    expect(last_response.status).to eq 200

  end

  it "should support rename_to" do
    s3 = AWS::S3.new(
      :access_key_id => "...",
      :secret_access_key => "...")   
    s3.buckets.create('test1')
    bucket = s3.buckets[:test]
    expect(bucket.exists?).to be true
    object = bucket.objects['test.file']

    initial_hash = Digest::MD5.hexdigest(File.read("#{File.dirname(__FILE__)}/../public/images/spacer.gif"))
    object.write(:file => "#{File.dirname(__FILE__)}/../public/images/spacer.gif")
    expect(Digest::MD5.hexdigest(object.read())).to eq initial_hash
    expect(object.exists?).to be true
    
    object.rename_to("test2.file")
    
    renamed_object = bucket.objects['test2.file']
    expect(renamed_object.exists?).to be true
    
  end
end
