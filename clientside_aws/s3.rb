require 'builder'

helpers do
  def list_buckets
    buckets = AWS_REDIS.keys 's3:bucket:*'

    xml = Builder::XmlMarkup.new
    xml.instruct!
    xml.ListAllMyBucketsResult(xmlns: 'http://s3.amazonaws.com/doc/2006-03-01') do
      xml.Owner do
        xml.tag!(:ID, UUID.new.generate)
        xml.tag!(:DisplayName, 'Fake Owner')
      end
      xml.Buckets do
        buckets.each do |bucket|
          xml.Bucket do
            xml.tag!(:Name, bucket.split(':').last)
            xml.tag!(:CreationDate, Time.at(AWS_REDIS.hget(bucket, 'created_at').to_i).xmlschema)
          end
        end
      end
    end

    content_type :xml
    xml.target!
  end

  def list_objects(bucket)
    xml = Builder::XmlMarkup.new
    xml.instruct!
    xml.ListBucketResult(xmlns: 'http://doc.s3.amazonaws.com/2006-03-01') do
      objects = AWS_REDIS.keys "s3:bucket:#{bucket}:*"
      xml.tag!(:Name, bucket)
      xml.tag!(:KeyCount, objects.length)
      xml.tag!(:Prefix, nil)
      xml.tag!(:Marker, nil)
      xml.tag!(:MaxKeys, 1000)
      xml.tag!(:IsTruncated, false)

      objects.each do |object|
        prefix = params.key?('prefix') ? params['prefix'] : nil
        next unless prefix.nil? || \
                    object.start_with?("s3:bucket:#{bucket}:#{prefix}")

        xml.Contents do
          key = AWS_REDIS.hget object, 'key'
          last_modified = AWS_REDIS.hget object, 'last_modified'
          etag = AWS_REDIS.hget object, 'etag'
          size = AWS_REDIS.hget object, 'size'

          xml.tag!(:Key, key)
          xml.tag!(:LastModified, Time.at(last_modified.to_i).xmlschema)
          xml.tag!(:ETag, etag)
          xml.tag!(:Size, size)
          xml.tag!(:Storage, 'STANDARD')
          xml.Owner do
            xml.tag!(:ID, UUID.new.generate)
            xml.tag!(:DisplayName, 'fake@example.com')
          end
        end
      end
    end

    content_type :xml
    xml.target!
  end

  def objectNotFound
    xml = Builder::XmlMarkup.new
    xml.instruct!
    xml.Error do
      xml.tag!(:Code, 'NoSuchKey')
      xml.tag!(:Message, 'The specified key does not exist.')
    end
    content_type :xml
    xml.target!
  end

  def download_file(bucket, obj_name)
    obj_key = "s3:bucket:#{bucket}:#{obj_name}"
    (AWS_REDIS.hget obj_key, 'body').force_encoding('UTF-8')
  end
end

# Get all of the buckets
#   Host: s3[.-][us-mockregion-1].amazonaws.com
get %r{/s3.*?\.amazonaws\.com/?} do
  list_buckets

  status 200
end

# Get bucket
#   Host: bucket-name.s3[.-][us-mockregion-1].amazonaws.com
get %r{/(.*?)\.(s3.*?\.amazonaws\.com)/?$} do
  bucket = params[:captures][0]
  halt 404 unless AWS_REDIS.exists "s3:bucket:#{bucket}"
  list_objects(bucket)
end

# Get a file a bucket
#   Host: bucket-name.s3[.-][us-mockregion-1].amazonaws.com/file-name
get %r{/(.*?)\.(s3.*?\.amazonaws\.com)?/(.+)} do
  bucket = params[:captures][0]
  file_name = params[:captures][2]

  halt 404, objectNotFound if AWS_REDIS.hget("s3:bucket:#{bucket}:#{file_name}", 'body').nil?

  body = download_file(bucket, file_name)
  content_type = AWS_REDIS.hget("s3:bucket:#{bucket}:#{file_name}", 'content-type')
  response.headers['content-type'] = content_type.nil? ? 'html' : content_type
  # response.headers["Content-Length"] = body.length.to_s
  response.headers['etag'] = Digest::MD5.hexdigest(body)
  response.body = body

  status 200
end

# Bucket creation
#   Host: bucket-name.s3[.-][us-mockregion-1].amazonaws.com
put %r{/(.*?)\.(s3\.?.*?\.amazonaws\.com)/?$} do
  bucket = params[:captures][0]
  AWS_REDIS.hset "s3:bucket:#{bucket}", 'created_at', Time.now.to_i

  status 200
end

# Upload file into a bucket
#   Host: bucket-name.s3[.-][us-mockregion-1].amazonaws.com/file-name
put %r{/(.*?)\.s3\.(.*?\.amazonaws\.com)?/(.+)} do
  bucket = params[:captures][0]
  file_name = params[:captures][2]

  # upload the file (chunking not implemented) to fake S3
  if file_name && bucket
    file_name = file_name[1..-1] if '/' == file_name[0]
    body_send = AWS::Core.testing ? params[:body] : request.body.read
    # Handle the copy_XXX case
    if (body_send.nil? || body_send.empty?) && (env.key?('HTTP_X_AMZ_COPY_SOURCE') || env.key?('x-amz-copy-source'))
      copy_source = env['HTTP_X_AMZ_COPY_SOURCE'] || env['x-amz-copy-source']
      if copy_source.start_with?('/')
        (_extra, srcbucket, srcfile) = copy_source.split('/')
      else
        (srcbucket, srcfile) = copy_source.split('/')
      end
      body_send = download_file(srcbucket, srcfile)
    end

    AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_name}", 'body', body_send
    AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_name}", 'key', file_name
    AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_name}", 'last_modified', Time.now.to_i
    AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_name}", 'size', body_send.length
    AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_name}", 'etag', Digest::MD5.hexdigest(body_send)

    %w(content-type Content-Type CONTENT_TYPE).each do |content_type_key|
      next unless env.key?(content_type_key)
      AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_name}",
                     'content-type',
                     env[content_type_key]
      break
    end
  end

  status 200
end

# Delete file from a bucket
#   Host: bucket-name.s3[.-][us-mockregion-1].amazonaws.com/file-name
delete %r{/(.*?)\.s3\.(.*?\.amazonaws\.com)?/(.+)} do
  bucket = params[:captures][0]
  file_name = params[:captures][2]
  AWS_REDIS.del "s3:bucket:#{bucket}:#{file_name}"

  status 200
end

# post %r{/s3(.*?\.amazonaws\.com)?/([^/]+)/?} do
#   # upload the file (chunking not implemented) to fake S3
#   bucket = params[:captures][1]
#   file_name = params[:key]
#   if file_name
#     file_name = file_name[1..-1] if file_name.start_with? '/'
#     body_send = params[:file]
#     body_send = body_send[:tempfile].read unless AWS::Core.testing
#
#     AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_name}", 'body', body_send
#     if env.key?('content-type')
#       AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_name}", 'content-type', env['content-type']
#     elsif env.key?('CONTENT_TYPE')
#       AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_name}", 'content-type', env['CONTENT_TYPE']
#     end
#   end
#   status 200
# end
