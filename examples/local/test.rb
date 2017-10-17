require 'rubygems'
require 'clientside_aws'

ClientsideAws.configure do |config|
 config.host = 'localhost'
 config.port = 5567
end

config = { region: 'us-mockregion-1',
           access_key_id: '...',
           secret_access_key: '...' }

Aws.config.update(config)
AWS.config(config)

s3 = Aws::S3::Client.new
s3.create_bucket(bucket: 'test')

bucket = Aws::S3::Resource.new.bucket('test')

# Now, store a JSON document
json_value = { foo: 'bar' }.to_json
object = bucket.object('test.json')
object.put(body: json_value, content_type: 'application/json')

object = bucket.object('test.json')

puts object.get.body.read


puts "Done"
