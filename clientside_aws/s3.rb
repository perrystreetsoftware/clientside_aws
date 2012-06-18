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
  
  def downloadFile(bucket, obj_name)
    obj_key = "s3:bucket:#{bucket}:#{obj_name}"
    return AWS_REDIS.hget obj_key, 'body'
  end
end 

get "/s3/" do 
  if env['SERVER_NAME'].match(/\./)
    bucket = env['SERVER_NAME'].split(".").first
    list_objects(bucket)
  else
    list_buckets
  end
end

get "/s3/*" do
   # handle S3 downloading from the 'servers'
   if env['SERVER_NAME'].match(/\./)
   
     # get the bucket
     bucket = env['SERVER_NAME'].split(".").first
     
     # get the file
     file = params[:splat]
     downloadFile(bucket, file) 
   else
     puts "May want to check yourself before you wreck yourself"
     # 'puts response.inspect' # gives details for debug
   end
end

put "/s3/*" do 
  # upload the file (chunking not implemented) to fake S3
  if params[:splat]
    file_location = params[:splat]
    bucket = env['SERVER_NAME'].split(".").first
    if ENV['RACK_ENV'] == 'development'
      body_send = request.body.read
    else 
      body_send = params[:body]
    end
    AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_location}", "body", body_send
  else
    # this is just figuring out when the bucket was created
    bucket = env['SERVER_NAME'].split(".").first
    AWS_REDIS.hset "s3:bucket:#{bucket}", "created_at", Time.now.to_i
  end
  200
end
