AWS::Core::Configuration.module_eval do
  port = ENV['RACK_ENV'] == 'test' ? "4568" : "4567"
  add_service "DynamoDB", "dynamo_db", "localhost:#{port}/dynamodb"
  add_service 'SQS', 'sqs', "localhost:#{port}/sqs"
  add_service 'S3', 's3', "localhost:#{port}/s3"
end


module AWS
  module Core
    class Client
      #puts ENV['RACK_ENV']
      if ENV['RACK_ENV'] == 'test'
        require 'rack/test'
        include Rack::Test::Methods
      else
        require 'httparty'
      end
      
      def app
        Sinatra::Application
      end
      
      private
      def make_sync_request response

        if response.http_request.host.match(/localhost/)
          headers = Hash.new
          response.http_request.headers.each do |k,v|
            headers[k] = v
          end
        
          params = Hash.new
          response.http_request.params.each do |p|
            params[p.name] = p.value
          end
        
          path = response.http_request.path
          body = response.http_request.body
        
          mock_response = nil
          if response.http_request.http_method == "POST"
            if ENV['RACK_ENV'] == 'test'
              new_path = URI.parse("http://#{response.http_request.host}#{path}").path
              post new_path, body, headers.merge('SERVER_NAME' => response.http_request.host)
              mock_response = last_response
            else
              mock_response = HTTParty::post("http://#{response.http_request.host}#{path}", :headers => headers, :body => body)
            end
          elsif response.http_request.http_method == "GET"   
            if ENV['RACK_ENV'] == 'test'
              new_path = URI.parse("http://#{response.http_request.host}#{path}").path
              get new_path, params, headers.merge('SERVER_NAME' => response.http_request.host)
              mock_response = last_response
            else
              mock_response = HTTParty::get("http://#{response.http_request.host}#{path}", :headers => headers, :query => params)    
            end
          elsif response.http_request.http_method == "HEAD"  
            #NOTE: a head request via AWS breaks the specifications when there is an error
            #      We need to send a GET request instead of head in case there is an XML 
            #      body attached to the response
            params['head_request'] = 1
            if ENV['RACK_ENV'] == 'test'
              new_path = URI.parse("http://#{response.http_request.host}#{path}").path
              get new_path, params, headers.merge('SERVER_NAME' => response.http_request.host)
              mock_response = last_response
            else
              mock_response = HTTParty::get("http://#{response.http_request.host}#{path}", :headers => headers, :query => params)
            end  
          elsif response.http_request.http_method == "DELETE"
            if ENV['RACK_ENV'] == 'test'
              new_path = URI.parse("http://#{response.http_request.host}#{path}").path
              delete new_path, params, headers.merge('SERVER_NAME' => response.http_request.host)
              mock_response = last_response
            else
              mock_response = HTTParty::delete("http://#{response.http_request.host}#{path}", :headers => headers, :query => params)
            end
          elsif response.http_request.http_method == "PUT"
            if ENV['RACK_ENV'] == 'test'
              new_path = URI.parse("http://#{response.http_request.host}#{path}").path
              params[:body] = body
              put new_path, params, headers.merge('SERVER_NAME' => response.http_request.host)
              mock_response = last_response
            else
              params[:body] = body
              if not headers['content-length'].nil?
                headers['content-length'] = headers['content-length'].to_s
              else 
                headers['content-length'] = "0"
              end
              mock_response = HTTParty::put("http://#{response.http_request.host}#{path}", :query =>params, :headers => headers, :body=> body)
            end
          end
        
          response.http_response = http_response =
            Http::Response.new
          if not mock_response.body.nil?
            # there is no body for some requests that are multi-part messages
            http_response.body = mock_response.body
          end

          http_response.status = mock_response.respond_to?(:status) ? mock_response.status : mock_response.code
          http_response.headers = mock_response.headers
          response.signal_success unless not mock_response.ok?
          populate_error(response)
          response
        else
          retry_server_errors do

            response.http_response = http_response =
              Http::Response.new

            @http_handler.handle(response.http_request, http_response)

            populate_error(response)
            response.signal_success unless response.error
            response

          end
        end
      end
      
      def build_request(name, options, &block)
        # we dont want to pass the async option to the configure block
        opts = options.dup
        opts.delete(:async)
        
        http_request = new_request
        
        # configure the http request
        http_request.host = endpoint
        http_request.proxy_uri = config.proxy_uri
        http_request.use_ssl = config.use_ssl?
        http_request.ssl_verify_peer = config.ssl_verify_peer?
        http_request.ssl_ca_file = config.ssl_ca_file if config.ssl_ca_file
        http_request.ssl_ca_path = config.ssl_ca_path if config.ssl_ca_path
        
        send("configure_#{name}_request", http_request, opts, &block)
        http_request.headers["user-agent"] = user_agent_string
        
        unless http_request.host.match(/localhost/)
          http_request.add_authorization!(signer)        
        end
        
        http_request
      end
    end
  end
end

module AWS
  class SQS

    # @private
    class Request < Core::Http::Request

      def path
        url_param = params.find { |p| p.name == "QueueUrl" }
        url_param ? "/#{url_param.value}" : nil
      end

      def host
        @host
      end
    end
  end
end
