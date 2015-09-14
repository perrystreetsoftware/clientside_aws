post %r{/kinesis(\.(\w+?)\.amazonaws\.com)?/(.*)} do
  if env["REQUEST_METHOD"] == "POST"
    args = JSON::parse(env['rack.input'].read)
  else
    args = env['rack.request.form_hash']
  end

  AWS_REDIS.zadd "kinesis:#{args['StreamName']}", Time.now.to_i, Base64.decode64(args['Data'])

  200
end
