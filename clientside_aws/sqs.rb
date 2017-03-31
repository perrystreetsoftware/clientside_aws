SQS_DEFAULT_VISIBILITY_TIMEOUT = \
  (ENV['SQS_VISIBILITY_TIMEOUT'] || 60 * 60 * 6).to_i

helpers do
  def get_queue_url
    queue_name = params[:QueueName]

    xml = Builder::XmlMarkup.new
    xml.instruct!

    xml.GetQueueUrlResponse do
      xml.GetQueueUrlResult do
        xml.tag!(:QueueUrl, queue_name)
      end
      xml.ResponseMetadata do
        xml.tag!(:RequestId, UUID.new.generate)
      end
    end

    content_type :xml
    xml.target!
  end

  def get_queue_attributes
    queue = params[:QueueUrl]

    xml = Builder::XmlMarkup.new
    xml.instruct!
    xml.GetQueueAttributesResponse do
      xml.GetQueueAttributesResult do
        xml.Attribute do
          xml.tag!(:Name, 'ApproximateNumberOfMessages')
          xml.tag!(:Value, (AWS_REDIS.llen queue))
        end
        xml.Attribute do
          xml.tag!(:Name, 'ApproximateNumberOfMessagesNotVisible')
          xml.tag!(:Value, (AWS_REDIS.keys 'sqs:pending:*').length)
        end
      end
      xml.ResponseMetadata do
        xml.tag!(:RequestId, UUID.new.generate)
      end
    end

    content_type :xml
    xml.target!
  end

  def delete_message
    AWS_REDIS.del("sqs:pending:#{params['ReceiptHandle']}")
    200
  end

  def delete_message_batch
    deleted_messages = []
    keys = params.keys.select { |k| k =~ /DeleteMessageBatchRequestEntry/ }
    keys.each do |k|
      AWS_REDIS.del("sqs:pending:#{params[k]}") if k =~ /ReceiptHandle$/
      deleted_messages << params[k] if k =~ /Id$/
    end

    xml = Builder::XmlMarkup.new
    xml.instruct!
    xml.DeleteMessageBatchResponse do
      xml.DeleteMessageBatchResult do
        deleted_messages.each do |msg_id|
          xml.DeleteMessageBatchResultEntry do
            xml.tag!(:Id, msg_id)
          end
        end
      end
      xml.ResponseMetadata do
        xml.tag!(:RequestId, UUID.new.generate)
      end
    end

    content_type :xml
    xml.target!
  end

  def receive_message
    queue = params[:QueueUrl]
    max_messages = params[:MaxNumberOfMessages].to_i
    max_messages = 1 if max_messages.zero?

    xml = Builder::XmlMarkup.new
    xml.instruct!

    if AWS_REDIS.llen(queue).zero?
      xml.ReceiveMessageResponse do
        xml.ReceiveMessageResult do
        end
        xml.ResponseMetadata do
          xml.tag!(:RequestId, UUID.new.generate)
        end
      end

      return xml.target!
    end

    results_json = []
    max_messages.times do
      raw_message = AWS_REDIS.rpop queue
      results_json << JSON.parse(raw_message.force_encoding('UTF-8'))
      break if (AWS_REDIS.llen queue).zero?
    end

    xml.ReceiveMessageResponse do
      xml.ReceiveMessageResult do
        results_json.each do |result|
          xml.Message do
            xml.tag!(:MessageId, result['MessageId'])
            xml.tag!(:ReceiptHandle, result['ReceiptHandle'])
            xml.tag!(:MD5OfBody, Digest::MD5.hexdigest(result['MessageBody']))
            xml.tag!(:Body, result['MessageBody'])
            xml.Attribute do
              xml.tag!(:Name, 'SenderId')
              xml.tag!(:Value, '1')
            end
            xml.Attribute do
              xml.tag!(:Name, 'SentTimestamp')
              xml.tag!(:Value, result['Timestamp'])
            end
            xml.Attribute do
              xml.tag!(:Name, 'ReceiptHandle')
              xml.tag!(:Value, result['Timestamp'])
            end
            xml.Attribute do
              xml.tag!(:Name, 'ApproximateReceiveCount')
              xml.tag!(:Value, '1')
            end
            xml.Attribute do
              xml.tag!(:Name, 'ApproximateFirstReceiveTimestamp')
              xml.tag!(:Value, result['Timestamp'] * 1000)
            end
          end
          redis_key = "sqs:pending:#{result['ReceiptHandle']}"
          payload = { queue: queue, message: result, received: Time.now }
          AWS_REDIS.set(redis_key, payload.to_json)
        end
      end
      xml.ResponseMetadata do
        xml.tag!(:RequestId, results_json.first['RequestId'])
      end
    end

    content_type :xml
    xml.target!
  end

  def send_message_batch
    queue = params[:QueueUrl]
    idx = 1
    loop do
      break unless params["SendMessageBatchRequestEntry.#{idx}.MessageBody"]
      send_message(queue, params["SendMessageBatchRequestEntry.#{idx}.MessageBody"])
      idx += 1
    end

    halt 200
  end

  def send_message(queue, message_body)
    message_id = UUID.new.generate
    request_id = UUID.new.generate
    msg = {
      MessageBody: message_body,
      MessageId: message_id,
      RequestId: request_id,
      Timestamp: Time.now.to_i,
      ReceiptHandle: Base64.encode64(message_id).strip
    }
    AWS_REDIS.lpush(queue, msg.to_json)

    xml = Builder::XmlMarkup.new
    xml.instruct!
    xml.SendMessageResponse do
      xml.SendMessageResult do
        xml.tag!(:MD5OfMessageBody, Digest::MD5.hexdigest(message_body))
        xml.tag!(:MessageId, message_id)
      end
      xml.ResponseMetadata do
        xml.tag!(:RequestId, request_id)
      end
    end

    content_type :xml
    xml.target!
  end

  def __check_pending
    AWS_REDIS.keys('sqs:pending:*').each do |key|
      json = AWS_REDIS.get(key).to_s.force_encoding("UTF-8")
      begin
        payload = JSON.parse(json)
        time_received = Time.parse(payload['received'])
        since_received = Time.now - time_received

        if since_received > SQS_DEFAULT_VISIBILITY_TIMEOUT
          AWS_REDIS.lpush(payload['queue'], payload['message'].to_json)
          AWS_REDIS.del(key)
        end
      rescue => e
        puts "INVALID PENDING PAYLOAD: #{e.message} #{json} #{e.backtrace}"
        STDOUT.flush
        AWS_REDIS.del(key)
      end
    end
  end
end

post %r{/sqs(\.(\w+?)\.amazonaws\.com)?/?(.*)} do
  __check_pending

  case params[:Action]
  when 'SendMessage'
    send_message(params[:QueueUrl], params[:MessageBody])
  when 'SendMessageBatch'
    send_message_batch
  when 'ReceiveMessage'
    receive_message
  when 'DeleteMessage'
    delete_message
  when 'DeleteMessageBatch'
    delete_message_batch
  when 'GetQueueAttributes'
    get_queue_attributes
  when 'GetQueueUrl'
    get_queue_url
  else
    halt 500, "Unknown action #{params.inspect}"
  end
end
