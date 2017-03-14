$LOAD_PATH << "#{File.dirname(__FILE__)}/../"

require 'aws-sdk'
require 'aws-sdk-v1'
require 'spec/spec_helper'

describe 'Profiles Spec' do
  include Rack::Test::Methods
  def app
    Sinatra::Application
  end

  it 'v1: should post to SQS okay' do
    sqs = AWS::SQS.new

    queue_name = 'http://sqs.us-mockregion-1.amazonaws.com/v1/test'
    (1..5).each do |i|
      sqs.queues.named(queue_name).send_message("test#{i}")
    end

    idx = 1
    sqs.queues.named(queue_name).poll(idle_timeout: 3) do |msg|
      expect(msg.body).to eq "test#{idx}"
      msg.delete
      idx += 1
      break if idx > 5
    end

    sqs.queues.named(queue_name).send_message('test')

    expect(sqs.queues.named(queue_name).approximate_number_of_messages).to eq 1
  end

  it 'v2: should post to SQS okay' do
    old_blackout_time = SQS_DEFAULT_VISIBILITY_TIMEOUT
    SQS_DEFAULT_VISIBILITY_TIMEOUT = 5

    client = Aws::SQS::Client.new
    resource = Aws::SQS::Resource.new(client: client)
    queue =
      resource.get_queue_by_name(
        queue_name: 'http://sqs.us-mockregion-1.amazonaws.com/v2/test'
      )

    (1..5).each do |i|
      queue.send_message(message_body: "test#{i}")
    end

    poller = Aws::SQS::QueuePoller.new(queue.url)

    idx = 1
    poller.poll(idle_timeout: 1) do |msg|
      expect(msg.body).to eq "test#{idx}"
      idx += 1
    end

    sent_msg = queue.send_message(message_body: 'test')
    expect(queue.attributes['ApproximateNumberOfMessages'].to_i).to eq 1

    poller.poll(idle_timeout: 1, skip_delete: true) do |msg|
      expect(msg.body).to eq 'test'
      expect(sent_msg.message_id).to eq msg.message_id
    end

    expect(queue.attributes['ApproximateNumberOfMessages'].to_i).to eq 1
    sleep SQS_DEFAULT_VISIBILITY_TIMEOUT
    queue =
      resource.get_queue_by_name(
        queue_name: 'http://sqs.us-mockregion-1.amazonaws.com/v2/test'
      )
    expect(queue.attributes['ApproximateNumberOfMessages'].to_i).to eq 1

    poller.poll(idle_timeout: 1, skip_delete: true) do |msg|
      expect(msg.body).to eq 'test'
      expect(sent_msg.message_id).to eq msg.message_id
      poller.delete_message(msg)
    end

    queue =
      resource.get_queue_by_name(
        queue_name: 'http://sqs.us-mockregion-1.amazonaws.com/v2/test'
      )
    expect(queue.attributes['ApproximateNumberOfMessages'].to_i).to eq 0

    SQS_DEFAULT_VISIBILITY_TIMEOUT = old_blackout_time
  end
end
