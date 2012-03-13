AWS::Core::Configuration.module_eval do
  add_service 'DynamoDB', 'dynamo_db', 'localhost:4567'
end


module AWS
  module Core
    class Client
      include Rack::Test::Methods
      
      def app
        Sinatra::Application
      end
      
      private
      def make_sync_request response

        if response.http_request.host == "localhost:4567"
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
        
          if response.http_request.http_method == "POST"
            post path, body, headers
          elsif response.http_request.http_method == "GET"
            get path, params, headers
          elsif response.http_request.http_method == "DELETE"
            delete path, params, headers
          elsif response.http_request.http_method == "PUT"
            put path, params, headers
          end
        
          response.http_response = http_response =
            Http::Response.new
          http_response.body = last_response.body
          http_response.status = last_response.status
          http_response.headers = last_response.headers
          response.signal_success unless not last_response.ok?
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
        
        unless http_request.host == "localhost:4567"
          http_request.add_authorization!(signer)        
        end
        http_request
      end
    end
  end
end