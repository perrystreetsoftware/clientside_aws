module AWS
  class Kinesis
    class Client < Core::JSONClient
      # Monkeypatch to save the last sent message
      class V20131202
        attr_reader :last_stream_name
        attr_reader :last_data
        attr_reader :last_partition_key

        def put_record(stream_name:, data:, partition_key:)
          @last_stream_name = stream_name
          @last_data = data
          @last_partition_key = partition_key
        end
      end
    end
  end
end
