$LOAD_PATH << "#{File.dirname(__FILE__)}/../"

require 'spec/spec_helper'

describe 'Profiles Spec' do
  include Rack::Test::Methods
  def app
    Sinatra::Application
  end
  # adding in for ability to access via other 'examples'

  it 'says hello' do
    get '/'
    expect(last_response.ok?).to be true
  end

  it 'v1: should post to S3 okay' do
    s3 = AWS::S3.new
    s3.buckets.create('test')
    bucket = s3.buckets['test']
    expect(bucket.exists?).to be true
    object = bucket.objects['test.file']

    initial_hash = \
      Digest::MD5.hexdigest(File.read("#{File.dirname(__FILE__)}" \
                                      '/../public/images/spacer.gif'))

    object.write(file: "#{File.dirname(__FILE__)}/../public/images/spacer.gif")
    expect(Digest::MD5.hexdigest(object.read)).to eq initial_hash
    expect(object.exists?).to be true

    expect(bucket.objects['asdfdsfasdf'].exists?).to be false

    object.delete
    expect(object.exists?).to be false

    json_value = { foo: 'bar' }.to_json
    object = bucket.objects['test.json']
    object.write(json_value, content_type: 'application/json')
    expect(object.read).to eq json_value
    expect(object.content_type).to eq 'application/json'
    expect(object.etag).to eq Digest::MD5.hexdigest(json_value)
  end

  it 'v2: should post to S3 okay' do
    s3 = Aws::S3::Client.new
    s3.create_bucket(bucket: 'test')

    bucket = Aws::S3::Resource.new.bucket('test')
    expect(bucket.exists?).to be true

    s3.put_object(bucket: 'test',
                  key: 'test.file',
                  body: File.new("#{File.dirname(__FILE__)}" \
                        '/../public/images/spacer.gif'))
    initial_hash = \
      Digest::MD5.hexdigest(File.read("#{File.dirname(__FILE__)}" \
                                      '/../public/images/spacer.gif'))

    bucket = Aws::S3::Resource.new.bucket('test')
    object = bucket.object('test.file')
    expect(Digest::MD5.hexdigest(object.get.body.read)).to eq initial_hash

    expect(object.exists?).to be true

    # expect(bucket.objects['asdfdsfasdf'].exists?).to be false

    object.delete
    object = bucket.object('test.file')

    expect(object.exists?).to be false
  end

  it 'v2: stores JSON document' do
    s3 = Aws::S3::Client.new
    s3.create_bucket(bucket: 'test')

    bucket = Aws::S3::Resource.new.bucket('test')
    expect(bucket.exists?).to be true

    # Now, store a JSON document
    json_value = { foo: 'bar' }.to_json
    object = bucket.object('test.json')
    object.put(body: json_value, content_type: 'application/json')

    object = bucket.object('test.json')
    expect(object.get.body.read).to eq json_value
    expect(object.content_type).to eq 'application/json'
    expect(object.etag).to eq Digest::MD5.hexdigest(json_value)
  end

  it 'v1: should support subpaths' do
    s3 = AWS::S3.new
    s3.buckets.create('test')
    bucket = s3.buckets[:test]
    expect(bucket.exists?).to be true
    object = bucket.objects['foo/bar/test.file']

    object.write(file: "#{File.dirname(__FILE__)}/../public/images/spacer.gif")
    expect(object.exists?).to be true

    s3_object = object.read
    expect(s3_object.length).to eq 43
  end

  it 'v2: should support subpaths' do
    s3 = Aws::S3::Client.new

    s3.create_bucket(bucket: 'test')
    bucket = Aws::S3::Resource.new.bucket('test')
    expect(bucket.exists?).to be true
    object = bucket.object('foo/bar/test.file')

    object.put(body: File.new("#{File.dirname(__FILE__)}" \
                              '/../public/images/spacer.gif'))
    expect(object.exists?).to be true

    gif_content = object.get.body.read
    expect(gif_content.length).to eq 43
  end

  it 'v1: should support rename_to' do
    s3 = AWS::S3.new
    s3.buckets.create('test1')
    bucket = s3.buckets[:test]
    expect(bucket.exists?).to be true
    object = bucket.objects['test1_v1.file']

    initial_hash = Digest::MD5.hexdigest(File.read("#{File.dirname(__FILE__)}/../public/images/spacer.gif"))
    object.write(file: "#{File.dirname(__FILE__)}/../public/images/spacer.gif")
    expect(Digest::MD5.hexdigest(object.read)).to eq initial_hash
    expect(object.exists?).to be true

    object.rename_to('test2_v1.file')

    renamed_object = bucket.objects['test2_v1.file']
    expect(renamed_object.exists?).to be true
    expect(renamed_object.read.nil?).to be false
  end

  it 'v2: should support rename_to' do
    s3 = Aws::S3::Client.new

    s3.create_bucket(bucket: 'test')
    bucket = Aws::S3::Resource.new.bucket('test')
    expect(bucket.exists?).to be true

    object = bucket.object('test_v2.file')
    object.put(body: File.new("#{File.dirname(__FILE__)}" \
                              '/../public/images/spacer.gif'))

    object2 = bucket.object('test2_v2.file')
    expect(object2.exists?).to be false
    object.move_to(object2)
    expect(object2.exists?).to be true
    expect(object.exists?).to be false
  end

  it 'v1: should list' do
    s3 = AWS::S3.new
    bucket_name = SecureRandom.hex(10)
    s3.buckets.create(bucket_name)
    bucket = s3.buckets[bucket_name]
    expect(bucket.exists?).to be true
    object = bucket.objects['test.file']
    object.write(file: "#{File.dirname(__FILE__)}/../public/images/spacer.gif")

    expect(bucket.objects.count).to eq 1
  end

  it 'v2: should list' do
    s3 = Aws::S3::Client.new

    bucket_name = SecureRandom.hex(10)
    s3.create_bucket(bucket: bucket_name)
    bucket = Aws::S3::Resource.new.bucket(bucket_name)
    expect(bucket.exists?).to be true

    object = bucket.object('test.file')
    object.put(body: File.new("#{File.dirname(__FILE__)}" \
                              '/../public/images/spacer.gif'))

    expect(bucket.objects.count).to eq 1
  end

  it 'v1: should respect prefix' do
    s3 = AWS::S3.new
    bucket_name = SecureRandom.hex(10)
    s3.buckets.create(bucket_name)
    bucket = s3.buckets[bucket_name]
    expect(bucket.exists?).to be true
    object = bucket.objects['apple.gif']
    object.write(file: "#{File.dirname(__FILE__)}/../public/images/spacer.gif")

    object = bucket.objects['banana.gif']
    object.write(file: "#{File.dirname(__FILE__)}/../public/images/spacer.gif")

    expect(bucket.objects.with_prefix('apple').count).to eq 1
  end

  it 'v2: should respect prefix' do
    s3 = Aws::S3::Client.new

    bucket_name = SecureRandom.hex(10)
    s3.create_bucket(bucket: bucket_name)
    bucket = Aws::S3::Resource.new.bucket(bucket_name)
    expect(bucket.exists?).to be true

    object = bucket.object('apple.gif')
    object.put(body: File.new("#{File.dirname(__FILE__)}" \
                              '/../public/images/spacer.gif'))

    object = bucket.object('banana.gif')
    object.put(body: File.new("#{File.dirname(__FILE__)}" \
                              '/../public/images/spacer.gif'))

    expect(bucket.objects(prefix: 'apple').count).to eq 1
  end
end
