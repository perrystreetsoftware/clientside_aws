require 'uuid'

module AWS
  # Mock SES and enable retrieval of last message sent
  # We also save messages to message_directory, if set
  class SimpleEmailService
    class SESMessage
      def initialize
        @id = UUID.new.generate
      end

      def successful?
        true
      end

      def data
        { message_id: @id }
      end
    end

    @@message_directory = nil
    @@sent_message = nil
    @@sent_email = nil
    def self.mock_clear_sent
      @@sent_email = nil
      @@sent_message = nil
    end

    def self.message_directory=(path)
      @@message_directory = path
    end

    def self.mock_sent_email(clear = nil)
      msg = @@sent_email
      mock_clear_sent if clear
      msg
    end

    def self.mock_sent_message(clear = nil)
      msg = @@sent_message
      mock_clear_sent if clear
      msg
    end

    def quotas
      { max_24_hour_send: 200, max_send_rate: 100.0, sent_last_24_hours: 22 }
    end

    def send_email(msg)
      ses_message = SESMessage.new
      to_adr = msg[:to]
      from_adr = msg[:from]
      _to_adr = to_adr[/(?<=<).*(?=>)/]
      _from_adr = from_adr[/(?<=<).*(?=>)/]
      fname = ses_message.data[:message_id]
      log_msg("#{fname}.txt", "#{msg[:subject]}\n\n#{msg[:body_text]}") if msg[:body_text]
      log_msg("#{fname}.html", msg[:body_html]) if msg[:body_html]
      @@sent_email = msg
      @@sent_message = ses_message
      ses_message
    end

    private

    def log_msg(file_name, content)
      email_dir = @@message_directory
      if email_dir
        email_dir += '/' unless email_dir.end_with? '/'
        FileUtils.mkdir_p(email_dir) unless File.directory?(email_dir)
        File.open("#{email_dir}#{file_name}", 'w') { |file| file.write(content) }
      end
    end
  end
end
