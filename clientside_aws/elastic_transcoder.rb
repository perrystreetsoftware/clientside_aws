helpers do
  def encode_video(source_key, dest_key, pipeline_id)
    pipeline = JSON.parse(AWS_REDIS.get("pipeline:#{pipeline_id}"))
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
    encoded_path = tmp.path + '.enc'
    faststart_path = tmp.path + '.fast'
    final_path = nil

    # Android is already encoded; ios needs re-encoding
    # Everyone gets faststart treatment
    ffmpeg_video(tmp.path, encoded_path)

    if File.exist?(encoded_path)
      final_path = if faststart_video(encoded_path, faststart_path)
                     faststart_path
                   else
                     encoded_path
                   end
    end

    if final_path && File.exist?(final_path)
      # Write
      file = File.open(final_path, 'rb')
      video = file.read
      file.close

      AWS_REDIS.hset output_obj_key, 'body', video
      AWS_REDIS.hset output_obj_key, 'content-type', 'video/mp4'

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
    end
  end

  def ffmpeg_video(path, output)
    flip = nil
    transpose = nil
    info = `avprobe #{path} 2>&1`
    match = info.match(/rotate\s+:\s(\d+)\s/)
    if match
      rotation = match[1]
      if rotation == '90'
        transpose = 1
      elsif rotation == '270'
        transpose = 2
      elsif rotation == '180'
        flip = true
      end
    end

    args = []

    args << 'avconv'
    args << '-y'

    args << '-i'
    args << path

    args << '-f'
    args << 'mp4'

    if transpose
      args << '-vf'
      args << "transpose=#{transpose}"
    elsif flip
      args << '-vf'
      args << 'vflip,hflip'
    end

    args << '-b:v'
    args << '900k'

    args << '-vcodec'
    args << 'libx264'

    args << '-ac'
    args << '1'

    args << '-ar'
    args << '44100'

    args << '-profile:v'
    args << 'baseline'

    # Just for avconv, because it complains about aac
    args << '-strict'
    args << 'experimental'

    args << output + '-tmp'

    encode_command = args.join(' ')
    _results = `#{encode_command} 2>&1`

    `mv #{output}-tmp #{output} 2>&1`
  end

  def faststart_video(path, output)
    unless `which qt-faststart`.empty?
      `qt-faststart #{path} #{output}`
      return true
    end

    false
  end

  def create_job(args)
    input_obj_name = args['Input']['Key']
    output_obj_name = args['Output']['Key']
    pipeline_id = args['PipelineId']

    encode_video(input_obj_name, output_obj_name, pipeline_id)

    content_type 'application/x-amz-json-1.0'
    { Job: {
      Id: 1,
      Input: args['Input'],
      Output: args['Output'],
      PipelineId: args['PipelineId']
    } }.to_json
  end

  def create_pipeline(args)
    if AWS_REDIS.get "pipeline:#{args['Name']}"
      pipeline_id = AWS_REDIS.get "pipeline:#{args['Name']}"
    else
      pipeline_id = SecureRandom.hex(10) + args['OutputBucket']
      AWS_REDIS.set "pipeline:#{pipeline_id}", args.to_json
      AWS_REDIS.set "pipeline:#{args['Name']}", pipeline_id
    end

    content_type 'application/x-amz-json-1.0'
    { Pipeline: {
      Id: pipeline_id,
      Name: args['Name'],
      Status: 'Completed',
      InputBucket: args['InputBucket'],
      OutputBucket: args['OutputBucket'],
      Role: args['Role'],
      Notifications: args['Notifications']
    } }.to_json
  end
end

post %r{/elastictranscoder\.(.+?)\.amazonaws\.com/?(.*)?} do
  args = JSON.parse(env['rack.input'].read)

  if args['Input'] && args['Output']
    create_job(args)
  else
    create_pipeline(args)
  end
end
