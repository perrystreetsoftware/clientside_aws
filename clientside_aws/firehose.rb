post %r{/firehose(\.(\w+?)\.amazonaws\.com)?/?(.*)} do
  args = if env['REQUEST_METHOD'] == 'POST'
           JSON.parse(env['rack.input'].read)
         else
           env['rack.request.form_hash']
         end

  AWS_REDIS.zadd "firehose:#{args['DeliveryStreamName']}",
                 Time.now.to_i,
                 Base64.decode64(args['Records'].to_json)

  200
end
