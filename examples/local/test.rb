require 'rubygems'
require 'aws-sdk-v1'
require 'aws-sdk'
require 'clientside_aws'
require 'pry'

ClientsideAws.configure do |config|
 config.host = 'localhost'
 config.port = 5567
end

config = { region: 'us-mockregion-1',
           access_key_id: '...',
           secret_access_key: '...' }

Aws.config.update(config)
AWS.config(config)


# s3 = Aws::S3::Client.new
# s3.create_bucket(bucket: 'test')

# bucket = Aws::S3::Resource.new.bucket('test')

# # Now, store a JSON document
# json_value = { foo: 'bar' }.to_json
# object = bucket.object('test.json')
# object.put(body: json_value, content_type: 'application/json')

# object = bucket.object('test.json')

# puts object.get.body.read

    AWS::ElasticTranscoder::Client.new.create_pipeline(
      name: 'SCRUFF_CHAT_VIDEO',
      input_bucket: 'foo',
      output_bucket: 'bar',
      role: '...',
      notifications: {
        progressing: '',
        completed: '',
        warning: '',
        error: '' })

puts "Done"
