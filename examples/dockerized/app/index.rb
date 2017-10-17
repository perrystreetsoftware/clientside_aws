require 'rubygems'
require 'clientside_aws'
require 'sinatra'

config = { region: 'us-mockregion-1',
           access_key_id: '...',
           secret_access_key: '...' }

Aws.config.update(config)
AWS.config(config)

get '/' do
  erb :index
end

post '/image' do
  s3 = Aws::S3::Client.new
  s3.create_bucket(bucket: 'test')

  bucket = Aws::S3::Resource.new.bucket('test')

  # Now, store an image
  object = bucket.object('image')
  file = File.open(params[:image][:tempfile].path, 'rb')
  image = file.read
  file.close

  object.put(body: image, content_type: 'image/jpeg')

  redirect '/'
end

get '/image' do
  bucket = Aws::S3::Resource.new.bucket('test')
  object = bucket.object('image')

  content_type 'image/jpeg'
  object.get.body.read
end
