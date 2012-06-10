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
  
  it "should post to SQS okay" do
    sqs = AWS::SQS.new(
      :access_key_id => "...",
      :secret_access_key => "...")
      
    (1..5).each do |i|
      response = sqs.queues["test"].send_message("test#{i}")
    end
    
    idx = 1
    sqs.queues["test"].poll(:idle_timeout => 3) { |msg|
      msg.body.should == "test#{idx}"
      idx += 1
      break if idx > 5
    }
    
  end  
  
end