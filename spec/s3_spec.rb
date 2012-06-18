require 'spec/spec_helper'
require 'aws-sdk'
require 'aws_mock'

describe 'Profiles Spec' do
  include Rack::Test::Methods
  def app
    Sinatra::Application
  end

  it "says hello" do
    get '/'
    last_response.should be_ok
  end
  
  it "should post to S3 okay" do
    s3 = AWS::S3.new(
      :access_key_id => "...",
      :secret_access_key => "...")
      
    s3.buckets.create('test')
    bucket = s3.buckets[:mybucket]
    
    s3.buckets.each do |bucket|
      puts "Bucket is #{bucket.name}"
    end
    
    bucket.objects.each do |object|
      puts object.inspect #=> no data is fetched from s3, just a list of keys
    end
    
    o = bucket.objects['test.file']
    initial_hash = Digest::MD5.hexdigest(File.read("#{File.dirname(__FILE__)}/../public/images/spacer.gif"))
    o.write(:file => "#{File.dirname(__FILE__)}/../public/images/spacer.gif")
    Digest::MD5.hexdigest(o.read()).should == initial_hash
    
    
  end  
  
end