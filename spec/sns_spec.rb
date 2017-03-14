$LOAD_PATH << "#{File.dirname(__FILE__)}/../"

require 'aws-sdk'
require 'aws-sdk-v1'
require 'spec/spec_helper'

describe 'Profiles Spec' do
  include Rack::Test::Methods
  def app
    Sinatra::Application
  end
  # adding in for ability to access via other 'examples'

  it 'says hello' do
    get '/'
    expect(last_response).to be_ok
  end

  it 'v1: should post to SNS okay' do
    sns = AWS::SNS.new

    response = sns.client.create_platform_endpoint(
      platform_application_arn: \
        'arn:aws:sns:us-east-1:999999999999:app/APNS/MYAPP',
      token: 'token'
    )
    expect(response.data[:endpoint_arn]).not_to be_nil
    expect(response.data[:endpoint_arn] =~ %r{endpoint/APNS}).not_to be nil

    response = sns.client.create_platform_endpoint(
      platform_application_arn: \
        'arn:aws:sns:us-east-1:999999999999:app/WNS/MYAPP',
      token: 'token'
    )
    expect(response.data[:endpoint_arn]).not_to be_nil
    expect(response.data[:endpoint_arn] =~ %r{endpoint/WNS}).not_to be nil

    response = sns.client.create_platform_endpoint(
      platform_application_arn: \
        'arn:aws:sns:us-east-1:999999999999:app/GCM/MYAPP',
      token: 'token'
    )
    expect(response.data[:endpoint_arn]).not_to be_nil
    expect(response.data[:endpoint_arn] =~ %r{endpoint/GCM}).not_to be nil
  end

  it 'v2: should post to SNS okay' do
    sns_client = Aws::SNS::Client.new

    response = sns_client.create_platform_endpoint(
      platform_application_arn: \
        'arn:aws:sns:us-east-1:999999999999:app/APNS/MYAPP',
      token: 'token'
    )
    expect(response.data[:endpoint_arn]).not_to be_nil
    expect(response.data[:endpoint_arn] =~ %r{endpoint/APNS}).not_to be nil

    response = sns_client.create_platform_endpoint(
      platform_application_arn: \
        'arn:aws:sns:us-east-1:999999999999:app/WNS/MYAPP',
      token: 'token'
    )
    expect(response.data[:endpoint_arn]).not_to be_nil
    expect(response.data[:endpoint_arn] =~ %r{endpoint/WNS}).not_to be nil

    response = sns_client.create_platform_endpoint(
      platform_application_arn: \
        'arn:aws:sns:us-east-1:999999999999:app/GCM/MYAPP',
      token: 'token'
    )
    expect(response.data[:endpoint_arn]).not_to be_nil
    expect(response.data[:endpoint_arn] =~ %r{endpoint/GCM}).not_to be nil
  end
end
