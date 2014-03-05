helpers do
  def encode_video(source_key, dest_key)

    pipeline = JSON.parse(AWS_REDIS.get("pipeline"))
    bucket = pipeline['InputBucket']
    input_obj_name = source_key
    input_obj_key = "s3:bucket:#{bucket}:#{input_obj_name}"

    bucket = pipeline['OutputBucket']
    output_obj_name = dest_key
    output_obj_key = "s3:bucket:#{bucket}:#{output_obj_name}"

    input_obj_body = AWS_REDIS.hget input_obj_key, 'body'
    
    tmp = Tempfile.new(source_key)
    tmp.write(input_obj_body)
    tmp.close
    
    # Setup paths
    encoded_path = tmp.path + ".enc"
    faststart_path = tmp.path + ".fast" 
    final_path = nil
    
    # Android is already encoded; ios needs re-encoding
    # Everyone gets faststart treatment
    ffmpeg_video(tmp.path, encoded_path)
    if File.exist?(encoded_path)
      if faststart_video(encoded_path, faststart_path)
        final_path = faststart_path
      else
        final_path = encoded_path
      end
    end

    if (final_path and File.exist?(final_path))
      # Write
      file = File.open(final_path, "rb")      
      video = file.read
      file.close
    
      AWS_REDIS.hset output_obj_key, "body", video
      AWS_REDIS.hset output_obj_key, "content-type", "video/mp4"
      
      begin
        File.delete(final_path) if File.exist?(final_path)
      rescue Exception => e
      end
      begin
        File.delete(encoded_path) if File.exist?(encoded_path)
      rescue Exception => e
      end
      begin
        File.delete(faststart_path) if File.exist?(faststart_path)
      rescue Exception => e
      end
      begin
        tmp.delete
      rescue Exception => e
      end
    else
    end
  end
  
  def ffmpeg_video(path, output)

    flip = nil
    transpose = nil
    info = `ffprobe #{path} 2>&1`
    match = info.match(/rotate\s+:\s(\d+)\s/)
    if match
      rotation = match[1]
      if rotation == "90"
        transpose = 1
      elsif rotation == "270"
        transpose = 2
      elsif rotation == "180"
        flip = true
      end
    end

    args = []

    args << "ffmpeg"
    args << "-y"

    args << "-i"
    args << path

    args << "-f"
    args << "mp4"

    if transpose
      args << "-vf"
      args << "transpose=#{transpose}"
    elsif flip
      args << "-vf"
      args << "vflip,hflip"
    end

    args << "-b:v"
    args << "900k"

    args << "-vcodec"
    args << "libx264"

    args << "-ac"
    args << "1"

    args << "-ar"
    args << "44100"

    args << "-profile:v"
    args << "baseline"

    args << output + "-tmp"

    encode_command = args.join(" ")
    results = `#{encode_command} 2>&1`
    `mv #{output}-tmp #{output} 2>&1`
  end
  
  def faststart_video(path, output)
    if `which qt-faststart`.length > 0
      `qt-faststart #{path} #{output}`
      return true
    end
    
    return false
  end  
end

post '/elastic_transcoder.localhost.amazonaws.com/2012-09-25/pipelines' do
  args = JSON::parse(env['rack.input'].read)
  
  AWS_REDIS.set "pipeline", args.to_json
  
  content_type "application/x-amz-json-1.0"  
  {:Pipeline => {
    :Id => UUID.new.generate,
    :Name => args['Name'],
    :Status => "Completed",
    :InputBucket => args['InputBucket'],
    :OutputBucket => args['OutputBucket'],
    :Role => args['Role'],
    :Notifications => args['Notifications']
  }}.to_json
end

post '/elastic_transcoder.localhost.amazonaws.com/2012-09-25/jobs' do
  args = JSON::parse(env['rack.input'].read)
    
  pipeline = JSON.parse(AWS_REDIS.get("pipeline"))
  bucket = pipeline['InputBucket']
  input_obj_name = args['Input']['Key']
  
  bucket = pipeline['OutputBucket']
  output_obj_name = args['Output']['Key']
  
  encode_video(input_obj_name, output_obj_name)

  content_type "application/x-amz-json-1.0"  
  {:Job => {
    :Id => 1,
    :Input => args['Input'],
    :Output => args['Output'],
    :PipelineId => args['PipelineId']
  }}.to_json
end
