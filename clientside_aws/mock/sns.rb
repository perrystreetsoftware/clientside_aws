module AWS
  class SNS
    class Client < Core::QueryClient
      # Monkeypatch to save the last sent message
      class V20100331
        attr_reader :last_msg

        def publish(target_arn:,
                    message_structure:,
                    message:,
                    message_attributes: nil)
          @last_msg = message
        end
      end
    end
  end
end
