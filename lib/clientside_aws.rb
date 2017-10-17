# frozen_string_literal: true

# Class to help you mock requests to AWS to instead point to a local
# docker container

require File.dirname(__FILE__) + '/clientside_aws/configuration'
require 'aws-sdk-v1'
require 'aws-sdk'

module ClientsideAws
  require File.dirname(__FILE__) + '/clientside_aws/version'
  require File.dirname(__FILE__) + '/clientside_aws/mock'

  class << self
    attr_accessor :configuration
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.reset
    @configuration = Configuration.new
  end

  def self.configure
    yield(configuration)
  end
end
