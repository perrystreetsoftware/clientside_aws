# Set your path to the redis-server binary here
ENV['RACK_ENV'] = 'test'

require 'index'
require 'sinatra'
require 'rspec'
require 'rack/test'
require 'aws_mock'

Sinatra::Base.set :environment, :test
Sinatra::Base.set :run, false
Sinatra::Base.set :raise_errors, true
Sinatra::Base.set :logging, false
Sinatra::Base.set :clientside_aws_testing, true

RSpec.configure do |config|
  config.include Rack::Test::Methods

  config.before(:suite) do
    PID1 = fork do
      $stdout = File.new('/dev/null', 'w')
      File.open('test1.conf', 'w') { |f| f.write("port 6380\ndbfilename test1.rdb\nloglevel warning") }
      exec 'redis-server test1.conf'
    end
    puts "PID1 is #{PID1}\n\n"
    sleep(3)

    clean_redis

    config = { region: 'us-mockregion-1',
               access_key_id: '...',
               secret_access_key: '...' }

    begin
      Aws.config.update(config)
    rescue NoMethodError
      # aws-sdk is not imported in the project
    end

    begin
      AWS.config(access_key_id: '...',
                 secret_access_key: '...',
                 region: 'us-mockregion-1')
    rescue NoMethodError
      # aws-sdk-v1 is not imported in the project
    end
  end

  config.after(:suite) do
    clean_redis

    puts 'Killing redis-server'

    STDOUT.flush
    Process.kill('KILL', PID1)
    FileUtils.rm 'test1.rdb' if File.exist?('test1.rdb')
    FileUtils.rm 'test1.conf' if File.exist?('test1.conf')
    Process.waitall
  end
end

def clean_redis
  raise 'cannot flush' unless ENV['RACK_ENV'] == 'test'
  AWS_REDIS.flushdb
end
