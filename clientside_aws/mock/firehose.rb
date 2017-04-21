module Aws
  module Firehose
    class Client
      # Monkeypatch to save the last sent message
      attr_reader :last_stream_name
      attr_reader :last_records

      def put_record_batch(delivery_stream_name:, records:)
        @last_stream_name = delivery_stream_name
        @last_records = records
      end
    end
  end
end
