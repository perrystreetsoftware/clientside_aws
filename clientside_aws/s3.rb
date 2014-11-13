require 'builder'

helpers do
  def list_buckets
    buckets = AWS_REDIS.keys "s3:bucket:*"
    
    xml = Builder::XmlMarkup.new()
    xml.instruct!
    xml.ListAllMyBucketsResult(:xmlns => "http://doc.s3.amazonaws.com/2006-03-01") do
      xml.Owner do
        xml.tag!(:ID, UUID.new.generate)
        xml.tag!(:DisplayName, "Fake Owner")
      end
      xml.Buckets do
        buckets.each do |bucket|
          xml.Bucket do
            xml.tag!(:Name, bucket.split(":").last)
            xml.tag!(:CreationDate, Time.at(AWS_REDIS.hget(bucket, "created_at").to_i).xmlschema)
          end
        end
      end
    end
        
    content_type :xml
    xml.target!
  end
  
  def list_objects(bucket)
    
    xml = Builder::XmlMarkup.new()
    xml.instruct!
    xml.ListAllMyBucketsResult(:xmlns => "http://doc.s3.amazonaws.com/2006-03-01") do
      xml.tag!(:Name, bucket)
      xml.tag!(:Prefix, nil)
      xml.tag!(:Marker, nil)
      xml.tag!(:MaxKeys, 1000)
      xml.tag!(:IsTruncated, false)
      
      objects = AWS_REDIS.keys "s3:bucket:#{bucket}:*"
      objects.each do |object|
        xml.Contents do
          
          key = AWS_REDIS.hget object,  "key"
          last_modified = AWS_REDIS.hget object, "last_modified"
          etag = AWS_REDIS.hget object, "etag"
          size = AWS_REDIS.hget object, "size"
          
          xml.tag!(:Key, key)
          xml.tag!(:LastModified, Time.at(last_modified.to_i).xmlschema)
          xml.tag!(:ETag, etag)
          xml.tag!(:Size, size)
          xml.tag!(:Storage, "STANDARD")
          xml.Owner do
            xml.tag!(:ID, UUID.new.generate)
            xml.tag!(:DisplayName, "fake@example.com")
          end
        end
      end
    end
    content_type :xml
    xml.target!
  end
  
  def objectNotFound
    xml = Builder::XmlMarkup.new()
    xml.instruct!
    xml.Error do
      xml.tag!(:Code, "NoSuchKey")
      xml.tag!(:Message, "The specified key does not exist.")
    end
    content_type :xml
    xml.target!
  end


  def downloadFile(bucket, obj_name)
    obj_key = "s3:bucket:#{bucket}:#{obj_name}"
    return (AWS_REDIS.hget obj_key, 'body').force_encoding("UTF-8")
  end
    
end 

get %r{/s3(.*?\.amazonaws\.com)?/(.+?)/(.+)} do
  bucket = params[:captures][1]
  file_name = params[:captures][2]
  
  halt 404, objectNotFound if AWS_REDIS.hget("s3:bucket:#{bucket}:#{file_name}", "body").nil?

  body = downloadFile(bucket, file_name)
  content_type = AWS_REDIS.hget("s3:bucket:#{bucket}:#{file_name}", "content-type")
  response.headers["Content-Type"] = content_type.nil? ? 'html' : content_type
  # response.headers["Content-Length"] = body.length.to_s
  response.headers["ETag"] = Digest::MD5.hexdigest(body)
  response.body = body

  status 200
end

get %r{^/s3(.*?\.amazonaws\.com)?/(.+?)/?$} do 
  bucket = params[:captures][1]
  list_objects(bucket)
  status 200
end

get %r{^/s3(.*?\.amazonaws\.com)?/$} do 
  bucket = params[:captures][1]
  list_buckets
  status 200
end

delete %r{/s3(.*?\.amazonaws\.com)?/(.+?)/(.+)} do 
  bucket = params[:captures][1]
  file_name = params[:captures][2]
  AWS_REDIS.del "s3:bucket:#{bucket}:#{file_name}"
  status 200
end

put %r{/s3(.*?\.amazonaws\.com)?/(.+?)/(.+)} do
  bucket = params[:captures][1]
  file_name = params[:captures][2]

  # upload the file (chunking not implemented) to fake S3
  if file_name and bucket
    file_name = file_name[1..-1] if '/' == file_name[0]
    body_send = nil

    if ENV['RACK_ENV'] == 'development'
      body_send = request.body.read
    else 
      body_send = params[:body]
    end
    
    # Handle the copy_XXX case
    if ((body_send.nil? or body_send.length == 0) and (env.has_key?("HTTP_X_AMZ_COPY_SOURCE") or env.has_key?("x-amz-copy-source")))
      copy_source = env["HTTP_X_AMZ_COPY_SOURCE"] || env["x-amz-copy-source"]
      (srcbucket, srcfile) = copy_source.split("/")
      body_send = downloadFile(srcbucket, srcfile)
    end
    
    AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_name}", "body", body_send
    if env.has_key?('content-type')
      AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_name}", "content-type", env['content-type']
    elsif env.has_key?('CONTENT_TYPE')
      AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_name}", "content-type", env['CONTENT_TYPE']
    end
  end
  status 200
end

put %r{/s3(.*?\.amazonaws\.com)?/([^/]+?)/?$} do
  # bucket creation
  bucket = params[:captures][1]
  AWS_REDIS.hset "s3:bucket:#{bucket}", "created_at", Time.now.to_i
  status 200
end

post %r{/s3(.*?\.amazonaws\.com)?/([^/]+)/?} do
 # upload the file (chunking not implemented) to fake S3
 bucket = params[:captures][1]
 file_name = params[:key]
  if file_name
    file_name = file_name[1..-1] if file_name.start_with? '/'
    body_send = nil
    if ENV['RACK_ENV'] == 'development'
      body_send = params[:file][:tempfile].read
    else 
      body_send = params[:file]
    end
   AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_name}", "body", body_send
    if env.has_key?('content-type')
      AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_name}", "content-type", env['content-type']
    elsif env.has_key?('CONTENT_TYPE')
      AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_name}", "content-type", env['CONTENT_TYPE']
    end
  end
  status 200
end
