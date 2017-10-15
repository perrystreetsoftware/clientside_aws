# frozen_string_literal: true

# Helpfully explained here: http://lizabinante.com/blog/creating-a-configurable-ruby-gem/
module ClientsideAws
  class Configuration
    attr_accessor :host
    attr_accessor :port

    def initialize
      @host = 'aws'
      @port = 4567
    end
  end
end
