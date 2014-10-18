AWS::Core::Configuration.module_eval do
  ENV['AWS_REGION'] = "localhost"
  port = ENV['RACK_ENV'] == 'test' ? "4567" : "4568"
  add_service "DynamoDB", "dynamo_db", "localhost:#{port}/dynamodb"
  add_service 'SQS', 'sqs', "localhost:#{port}/sqs"
  add_service 'S3', 's3', "localhost:#{port}/s3"
  add_service 'ElasticTranscoder', 'elastic_transcoder', "localhost:#{port}/elastic_transcoder"
  add_service 'SimpleEmailService', 'simple_email_service', "localhost:#{port}/ses"
  add_service 'SNS', 'sns', "localhost:#{port}/sns"

  add_option :sqs_verify_checksums, false, :boolean => true
  add_option :override_port, ENV['RACK_ENV'] == 'test' ? "4567" : "4568"

end

module AWS
  module Core   
    class Client
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
        
          if not headers['content-length'].nil?
            headers['content-length'] = headers['content-length'].to_s
          else 
            headers['content-length'] = "0"
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
              host_and_port = response.http_request.host.match(config.override_port).nil? ? "#{response.http_request.host}:#{config.override_port}" : response.http_request.host
              mock_response = HTTParty::post("http://#{host_and_port}#{path}", :headers => headers, :body => body)
            end
          elsif response.http_request.http_method == "GET"   
            if ENV['RACK_ENV'] == 'test'
              new_path = URI.parse("http://#{response.http_request.host}#{path}").path
              get new_path, params, headers.merge('SERVER_NAME' => response.http_request.host)
              mock_response = last_response
            else
              host_and_port = response.http_request.host.match(config.override_port).nil? ? "#{response.http_request.host}:#{config.override_port}" : response.http_request.host
              mock_response = HTTParty::get("http://#{host_and_port}#{path}", :headers => headers, :query => params)    
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
              host_and_port = response.http_request.host.match(config.override_port).nil? ? "#{response.http_request.host}:#{config.override_port}" : response.http_request.host
              mock_response = HTTParty::get("http://#{host_and_port}#{path}", :headers => headers, :query => params)
            end  
          elsif response.http_request.http_method == "DELETE"
            if ENV['RACK_ENV'] == 'test'
              new_path = URI.parse("http://#{response.http_request.host}#{path}").path
              delete new_path, params, headers.merge('SERVER_NAME' => response.http_request.host)
              mock_response = last_response
            else
              host_and_port = response.http_request.host.match(config.override_port).nil? ? "#{response.http_request.host}:#{config.override_port}" : response.http_request.host
              mock_response = HTTParty::delete("http://#{host_and_port}#{path}", :headers => headers, :query => params)
            end
          elsif response.http_request.http_method == "PUT"
            if ENV['RACK_ENV'] == 'test'
              new_path = URI.parse("http://#{response.http_request.host}#{path}").path
              params[:body] = body
              put new_path, params, headers.merge('SERVER_NAME' => response.http_request.host)
              mock_response = last_response
            else
              host_and_port = response.http_request.host.match(config.override_port).nil? ? "#{response.http_request.host}:#{config.override_port}" : response.http_request.host
              mock_response = HTTParty::put("http://#{host_and_port}#{path}", :query => params, :headers => headers, :body=> body)
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
      
      def client_request name, options, &read_block
        return_or_raise(options) do
          log_client_request(options) do

            if config.stub_requests?

              response = stub_for(name)
              response.http_request = build_request(name, options)
              response.request_options = options
              response

            else

              client = self

              response = new_response do
                req = client.send(:build_request, name, options)
                req
              end

              response.request_type = name
              response.request_options = options

              if
                cacheable_request?(name, options) and
                cache = AWS.response_cache and
                cached_response = cache.cached(response)
              then
                cached_response.cached = true
                cached_response
              else

                # process the http request
                options[:async] ?
                make_async_request(response, &read_block) :
                  make_sync_request(response, &read_block)

                # process the http response
                response.on_success do
                  send("process_#{name}_response", response)
                  if cache = AWS.response_cache
                    cache.add(response)
                  end
                end

                # close files we opened
                response.on_complete do
                  if response.http_request.body_stream.is_a?(ManagedFile)
                    response.http_request.body_stream.close
                  end
                end

                response

              end

            end

          end
        end

      end


    end
  end
end

module AWS # override for constructing POST requests for client
  class S3
    class Client < Core::Client
      module Validators
        # this keeps it from fucking up our hostname
        def path_style_bucket_name? bucket_name
          true
        end
      end
    end
    
    class PresignedPost
      def secure?
        false
      end
      def url
        request = Request.new
        request.bucket = bucket.name
        parts = config.s3_endpoint.split(':')
        request.host = parts.shift
        parts = parts.join(':').split('/')
        request.port = parts.shift.to_i        
        request.key = parts.join('/')
        uri_class = secure? ? URI::HTTPS : URI::HTTP
        uri_class.build(:host => request.host, :path => request.path, :query => request.querystring, :port => request.port)
      end
    end
  end
end
