
$LOAD_PATH << "#{File.dirname(__FILE__)}/../"

require 'spec/spec_helper'
require 'aws-sdk'
require 'aws-sdk-v1'
require 'aws_mock'

describe 'Profiles Spec' do
  include Rack::Test::Methods
  def app
    Sinatra::Application
  end

  it 'v1: should post to transcoder okay' do
    guid = UUID.new.generate
    video_file = File.new("#{File.dirname(__FILE__)}" \
                          '/../public/images/stock_video.mp4')

    s3 = AWS::S3.new
    s3.buckets.create('test')
    bucket = s3.buckets['test']
    expect(bucket.exists?).to be true
    object = bucket.objects["#{guid}-video"]
    object.write(file: video_file)

    expect(AWS_REDIS.exists("s3:bucket:#{bucket.name}:#{guid}-video"))\
      .to be true
    object = bucket.objects["#{guid}-video"]
    expect(object.exists?).to be true
    expect(object.content_length).to be > 0

    transcoder = AWS::ElasticTranscoder::Client.new

    pipeline_name = 'SCRUFF'
    input_bucket = 'test'
    output_bucket = 'test'

    pipeline_response = transcoder.create_pipeline(
      name: pipeline_name,
      input_bucket: input_bucket,
      output_bucket: output_bucket,
      role: '...',
      notifications: {
        progressing: '',
        completed: '',
        warning: '',
        error: ''
      }
    )
    expect(last_response.ok?).to be true

    pipeline = pipeline_response.pipeline
    expect(pipeline.name).to eq pipeline_name
    expect(pipeline.input_bucket).to eq input_bucket
    expect(pipeline.output_bucket).to eq output_bucket

    transcoder.create_job(
      pipeline_id: pipeline.id,
      input: { key: "#{guid}-video",
               frame_rate: 'auto',
               resolution: 'auto',
               aspect_ratio: 'auto',
               interlaced: 'auto',
               container: 'auto' },
      output: { key: "#{guid}-video-encoded",
                thumbnail_pattern: '',
                rotate: 'auto',
                preset_id: 'fake-preset' }
    )
    expect(last_response.ok?).to be true

    expect(bucket.objects["#{guid}-video-encoded"].exists?).to be true
    expect(bucket.objects["#{guid}-video-encoded"].content_length).to be > 0
  end

  it 'v2: should post to transcoder okay' do
    guid = UUID.new.generate
    video_file = File.new("#{File.dirname(__FILE__)}" \
                          '/../public/images/stock_video.mp4')

    s3 = Aws::S3::Client.new
    s3.create_bucket(bucket: 'test')

    bucket = Aws::S3::Resource.new.bucket('test')
    expect(bucket.exists?).to be true

    s3.put_object(bucket: 'test',
                  key: "#{guid}-video",
                  body: video_file)

    expect(AWS_REDIS.exists("s3:bucket:#{bucket.name}:#{guid}-video"))\
      .to be true
    object = bucket.object("#{guid}-video")
    expect(object.exists?).to be true
    expect(object.content_length).to be > 0

    transcoder = Aws::ElasticTranscoder::Client.new

    pipeline_name = 'SCRUFF'
    input_bucket = 'test'
    output_bucket = 'test'

    pipeline_response = transcoder.create_pipeline(
      name: pipeline_name,
      input_bucket: input_bucket,
      output_bucket: output_bucket,
      role: '...',
      notifications: {
        progressing: '',
        completed: '',
        warning: '',
        error: ''
      }
    )
    expect(last_response.ok?).to be true

    pipeline = pipeline_response.pipeline
    expect(pipeline.name).to eq pipeline_name
    expect(pipeline.input_bucket).to eq input_bucket
    expect(pipeline.output_bucket).to eq output_bucket

    transcoder.create_job(
      pipeline_id: pipeline.id,
      input: { key: "#{guid}-video",
               frame_rate: 'auto',
               resolution: 'auto',
               aspect_ratio: 'auto',
               interlaced: 'auto',
               container: 'auto' },
      output: { key: "#{guid}-video-encoded",
                thumbnail_pattern: '',
                rotate: 'auto',
                preset_id: 'fake-preset' }
    )
    expect(last_response.ok?).to be true

    expect(bucket.object("#{guid}-video-encoded").exists?).to be true
    expect(bucket.object("#{guid}-video-encoded").content_length).to be > 0
  end
end
