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
    last_response.should be_ok
  end
  
  it "should post to SNS okay" do
    sns = AWS::SNS.new(
      :access_key_id => "...",
      :secret_access_key => "...")   
      
    sns.client.create_platform_endpoint(:platform_application_arn => "SNS_APPLICATION_ARN_IOS", :token => "token")
  end  
end