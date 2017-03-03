helpers do
  def create_platform_endpoint(platform_application_arn:)
    xml = Builder::XmlMarkup.new
    xml.instruct!

    xml.CreatePlatformEndpointResponse do
      xml.CreatePlatformEndpointResult do
        platform = if platform_application_arn =~ %r{app/APNS}
                     'endpoint/APNS/'
                   elsif platform_application_arn =~ %r{app/WNS}
                     'endpoint/WNS/'
                   elsif platform_application_arn =~ %r{app/GCM}
                     'endpoint/GCM/'
                   else
                     'endpoint/UNKNOWN/'
                   end

        xml.tag!(:EndpointArn,
                 'arn:aws:sns:us-east-1:999999999999:' \
                 "#{platform}MYAPP/#{UUID.new.generate}")
      end
    end

    content_type :xml
    xml.target!
  end
end

get %r{/sns\.(\w+?)\.amazonaws\.com/?(.*)} do
  200
end

post %r{/sns(\.(\w+?)\.amazonaws\.com)?/?(.*)} do
  case params[:Action]
  when 'CreatePlatformEndpoint'
    create_platform_endpoint(platform_application_arn:
      params['PlatformApplicationArn'])
  else
    200
  end
end
