clientside_aws
===================

Run selected AWS services via a docker container locally, for more effective development and testing.

## Install

In your gemfile:

    gem 'clientside_aws', require: 'clientside_aws'

## Features

- Write code on a plane: Interact with AWS services like S3, SQS and DynamoDb, without internet access
- No more tedious configuration of mocked responses in your unit tests
- Save time and money by avoiding the need for a 'test' account in AWS where you upload S3 files and interact with DynamoDb databases along with other developers on your team
- Instantly restore your development and test environments to known good states

Think about how 


This code is meant to be used by developers who are attempting to build web applications on AWS but wish to run client-side testing and validation. Presently, this project mocks DynamoDB and SQS.

While creating and tearing down "free-tier" SQS and DynamoDB databases may be an acceptable solution for some, the time required (tens of seconds or minutes) quickly makes TDD (test-driven development) impractical. Just like we can use an in-memory sqlite3-based solution for mocking Mysql databases with ActiveRecord, we can now  mock SQS and DynamoDB databases in memory using Redis.

To run this code, you will need ruby, sinatra, httparty, and the json and redis rubygems. I also use the sinatra/reloader gem to aid in development, but it is not necessary.

You will also need redis-server installed locally

Make sure redis-server is in your path

Then, from the command line, run:

    ruby spec/dynamodb_spec.rb
or

    ruby spec/sqs_spec.rb

That will run the unit tests against this code.

Overview
--------

This code works by overwriting the AWS service URLs in the aws-sdk gem, then monkeypatching the AWS::Core::Client request methods to use Rack's put, get, post and delete methods (see aws_mock.rb). This points to a Sinatra endpoint that processes the DynamoDB requests. Provided you are using the DynamoDB methods defined in aws-sdk when running tests and validations, the ruby client never knows it isn't talking to the real service.

I have not packaged this up as a gem, because it needs to be a standalone sinatra project so you can launch a server from the command line (see below). I am open to suggestions about how to make it easier/cleaner to include dynamodb_mock into your actual project; right now you have to use a require statement that has knowledge of your directory structure.

Adding to your project
---------------------------

First, if you plan on running any rspec unit tests, you should update the REDIS_PATH variable in spec_helper.rb to point to your redis binary.

To start clientside_aws stand-alone, from the command line, run:

    cd ~/clientside_aws/
    ruby index.rb -p 4568

This launches a Sinatra app, running on port 4568, that can respond to and support various services using the AWS protocol. You have your own, client-side SQS and DynamoDB server! If you are capable of mocking the requests in your language of choice to point to localhost:4568 you are ready to go. Included in this project is the code to mock in Ruby.

For example, here's how I added clientside_aws to my Sinatra project:

    configure :development do
      require 'clientside_aws'  
      DYNAMODB = AWS::DynamoDB.new(
        :access_key_id => "...",
        :secret_access_key => "...")
      # more config
    end

I can then access the DynamoDB API from my code using the standard ruby aws-sdk DynamoDB class, discussed in more detail here:
http://rubydoc.info/github/amazonwebservices/aws-sdk-for-ruby/master/AWS/DynamoDB

Assuming you are including the 'aws_mock' file, you can call DynamoDB just as you normally would in your code. For example:

    dynamo_db = AWS::DynamoDB.new(
      :access_key_id => "...",
      :secret_access_key => "...")

    visitors_table = dynamo_db.tables.create("visitors", 10, 5,
        :hash_key => { :creator_id => :number },
        :range_key => {:date => :number})

    visitors_table.hash_key = [:creator_id, :number]
    visitors_table.range_key = [:date, :number]

    (0..10).each do |idx|      
      visitors_table.items.put(:creator_id => 1, :date => Time.now.to_f - (60 * idx), :target_id => 10 + idx)
    end

You can check out the dynamodb_spec.rb file for more unit tests and sample DynamoDB ruby code.

If testing on a localhost(which you most likely are), you will need to add this line to your /etc/hosts file:

127.0.0.1  test.localhost

Amazon sticks the bucket to the front of the localhost to create a subdomain

TODO
--------------------

I am developing this code for my own test purposes as I go along. There are certainly bugs and I have not yet implemented all the DynamoDB methods. Code lacks support at this time for the following:

* Scan
* UpdateTable
* BatchGetItem

I also have very a limited test suite; I will expand as I can. Feel free to fork, add, and submit a pull request.

There are clearly many more AWS services one can mock up.

* * *

License
=======
MIT License (http://en.wikipedia.org/wiki/MIT_License). Some parts of this code were adapted from the aws-sdk project, which can be found at: https://github.com/amazonwebservices/aws-sdk-for-ruby and is itself licensed under the Apache 2.0 license.

Copyright (C) 2012 Perry Street Software, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
