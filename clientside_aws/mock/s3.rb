module AWS
  class S3
    class Bucket
      begin
        old_exists = instance_method(:exists?)
        define_method(:exists?) do
          begin
            old_exists.bind(self).call
          rescue Errors::NoSuchKey
            false # bucket does not exist
          end
        end
      rescue NameError
        # aws-sdk-v1 is not being used
      end
    end

    class PresignedPost
      @@host = nil
      @@port = nil
      def self.mock_host=(host)
        @@host = host
      end

      def self.mock_port=(port)
        @@port = port
      end

      def mock_host
        @@host || config.s3_endpoint.split(':').first
      end

      def mock_port
        @@port || config.s3_endpoint.split(':')[1].split('/').first.to_i
      end

      def url
        URI::HTTP.build(host: mock_host, path: "/s3/#{bucket.name}", port: mock_port)
      end
    end

    # class Client < Core::Client
    #   module Validators
    #     # this keeps it from fucking up our hostname
    #     def path_style_bucket_name?(_bucket_name)
    #       true
    #     end
    #   end
    # end

    # class S3Object
    #   def presign_v4(method, _options)
    #     if method == :read || method == :get
    #       "http://#{client.endpoint}/#{bucket.name}/#{key}"
    #     end
    #   end
    # end
  end
end
