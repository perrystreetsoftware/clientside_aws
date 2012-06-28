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
  status 200
end

get "/s3/*" do
   # handle S3 downloading from the 'servers'
   if env['SERVER_NAME'].match(/\./)
     # get the bucket
     bucket = env['SERVER_NAME'].split(".").first
     if AWS_REDIS.hget("s3:bucket:#{bucket}:#{params[:splat]}", "body").nil?
       # I can't find the object in the fake bucket!
       halt 404, objectNotFound
     else    
       file = params[:splat]
       if not params.has_key?('head_request')
         # download the file and send back
         response.body = downloadFile(bucket, file)
       end
       # using HTML because amazon's backend cracks open and finds what type it is and the browser will usually
       # handle this
       response.headers["Content-Type"] = 'html'
       response.headers["Content-Length"] =  downloadFile(bucket, file).length
       response.body  = downloadFile(bucket, file)
       return
     end  
   else
     puts "May want to check yourself before you wreck yourself"
     # 'puts response.inspect' # gives details for debug
   end
   status 200
end

delete "/s3/*" do 
  # delete the given key
  if env['SERVER_NAME'].match(/\./)
    bucket = env['SERVER_NAME'].split(".").first
    AWS_REDIS.del "s3:bucket:#{bucket}:#{params[:splat]}"
  end
  status 200
end


put "/s3/" do
  # bucket creation
  bucket = env['SERVER_NAME'].split(".").first
  AWS_REDIS.hset "s3:bucket:#{bucket}", "created_at", Time.now.to_i
  status 200
end

put "/s3/:file" do 
  # upload the file (chunking not implemented) to fake S3
  if params[:file]
    body_send = nil
    file_location = params[:file]
    bucket = env['SERVER_NAME'].split(".").first
    if ENV['RACK_ENV'] == 'development'
      body_send = request.body.read
    else 
      body_send = params[:body]
    end
    AWS_REDIS.hset "s3:bucket:#{bucket}:#{file_location}", "body", body_send
    
  end
  status 200
end




