helpers do
  def create_platform_endpoint
    xml = Builder::XmlMarkup.new()
    xml.instruct!
    
    xml.CreatePlatformEndpointResponse do
      xml.CreatePlatformEndpointResult do
        xml.tag!(:EndpointArn, "arn:#{UUID.new.generate}")
      end
    end
    
    content_type :xml
    xml.target!
  end
end

get %r{/sns.localhost.amazonaws.com/(.*)} do
  200
end

post %r{/sns.localhost.amazonaws.com/?(.*)} do
  case params[:Action]
  when "CreatePlatformEndpoint"
    create_platform_endpoint()
  else
    200
  end
end
