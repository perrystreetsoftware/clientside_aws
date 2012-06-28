helpers do
  
  def get_queue_url
    queue_name = params[:QueueName]

    xml = Builder::XmlMarkup.new()
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
    
    xml = Builder::XmlMarkup.new()
    xml.instruct!
    xml.GetQueueAttributesResponse do
      xml.GetQueueAttributesResult do
        xml.Attribute do
          xml.tag!(:Name, "ApproximateNumberOfMessages")
          xml.tag!(:Value, (AWS_REDIS.llen queue))
        end
        xml.Attribute do
          xml.tag!(:Name, "ApproximateNumberOfMessagesNotVisible")
          xml.tag!(:Value, (AWS_REDIS.keys "sqs:pending:*").length)
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
    AWS_REDIS.del "sqs:pending:#{params['ReceiptHandle']}"
    
    200
  end
  
  def receive_message
    queue = params[:QueueUrl]
    
    xml = Builder::XmlMarkup.new()
    xml.instruct!
    
    result_json = AWS_REDIS.rpop queue
    
    if result_json.nil?
      xml.ReceiveMessageResponse do
        xml.ReceiveMessageResult do
        end
      end
      xml.ResponseMetadata do
      end
      return xml.target!
    end
    
    AWS_REDIS.set "sqs:pending:#{params['ReceiptHandle']}", Time.now.to_i
    
    result = JSON.parse(result_json)
    
    xml.ReceiveMessageResponse do
      xml.ReceiveMessageResult do
        xml.Message do
          xml.tag!(:MessageId, result['MessageId'])
          xml.tag!(:ReceiptHandle, result['ReceiptHandle'])
          xml.tag!(:MD5OfBody, Digest::MD5.hexdigest(result['MessageBody']))
          xml.tag!(:Body, result['MessageBody'])
          xml.Attribute do
            xml.tag!(:Name, "SenderId")
            xml.tag!(:Value, "1")
          end
          xml.Attribute do
            xml.tag!(:Name, "SentTimestamp")
            xml.tag!(:Value, result['Timestamp'])
          end
          xml.Attribute do
            xml.tag!(:Name, "ReceiptHandle")
            xml.tag!(:Value, result['Timestamp'])
          end
        end
      end
      xml.ResponseMetadata do
        xml.tag!(:RequestId, result['RequestId'])
      end
    end    
    
    content_type :xml
    xml.target!
  end
  
  def send_message()
    queue = params[:QueueUrl]

    message_id = UUID.new.generate
    request_id = UUID.new.generate
    
    AWS_REDIS.lpush queue, {
      :MessageBody => params[:MessageBody], 
      :MessageId => message_id,
      :RequestId => request_id,
      :Timestamp => Time.now.to_i,
      :ReceiptHandle => Base64.encode64(message_id).strip}.to_json
      
    xml = Builder::XmlMarkup.new()
    xml.instruct!
    xml.SendMessageResponse do
      xml.SendMessageResult do
        xml.tag!(:MD5OfMessageBody, Digest::MD5.hexdigest(params[:MessageBody]))
        xml.tag!(:MessageId, message_id)
      end
      xml.ResponseMetadata do
        xml.tag!(:RequestId, request_id)
      end
    end    

    content_type :xml
    xml.target!
  end
  
end

post "/sqs/?" do
  case params[:Action]
  when "GetQueueUrl"
    get_queue_url()
  end
end

post %r{/sqs/(.*)} do
  case params[:Action]    
  when "SendMessage"
    send_message()
  when "ReceiveMessage"
    receive_message()
  when "DeleteMessage"
    delete_message()
  when "GetQueueAttributes"
    get_queue_attributes()
  end  
end