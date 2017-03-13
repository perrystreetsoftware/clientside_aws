module AWS
  module Core
    SQS_VISIBILITY_TIMEOUT = (ENV['SQS_VISIBILITY_TIMEOUT'] || 60 * 60 * 6).to_i
    class << self
      attr_accessor :testing
    end
    AWS::Core.testing = (ENV['RACK_ENV'] != "development")
  end
end
