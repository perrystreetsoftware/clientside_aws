post %r{/kinesis(\.(\w+?)\.amazonaws\.com)?/?(.*)} do
  args = if env['REQUEST_METHOD'] == 'POST'
           JSON.parse(env['rack.input'].read)
         else
           env['rack.request.form_hash']
         end

  AWS_REDIS.zadd "kinesis:#{args['StreamName']}",
                 Time.now.to_i,
                 Base64.decode64(args['Data'])

  200
end
