clientside_dynamodb
===================

This code is meant to be used by developers who are attempting to build web applications on DynamoDB but wish to run client-side testing and validation. While creating and tearing down "free-tier" DynamoDB databases may be an acceptable solution for some, the time required (tens of seconds or minutes) quickly makes TDD (test-driven development) impractical. Just like we can use an in-memory sqlite3-based solution for mocking Mysql databases with ActiveRecord, we can now use clientside_dynamodb to mock DynamoDB databases in memory using Redis.

To run this code, you will need ruby, sinatra, and the json and redis rubygems. I also use the sinatra/reloader gem to aid in development, but it is not necessary.

You will also need redis-server installed locally

Edit spec_helper.rb and configure the REDIS_PATH variable at the top to point to the install location of redis-server

Then, from the command line, run:

    ruby spec/dyndb_spec.rb

That will run the unit tests against this code.

To launch this code standalone, run:

    ruby index.rb

That will launch sinatra and run the code on localhost:4567

Overview
--------

This code works by overwriting the DynamoDB service URL in the aws-sdk gem, then monkeypatching the AWS::Core::Client request methods to use Rack's put, get, post and delete methods (see dynamodb_mock.rb). This points to a Sinatra endpoint that processes the DynamoDB requests. Provided you are using the DynamoDB methods defined in aws-sdk, when running tests and validations, the ruby client never knows it isn't talking to the real service.

TODO
--------------------

I am developing this code for my own test purposes as I go along. There are certainly bugs and I have not yet implemented all the DynamoDB methods. Code lacks support at this time for the following:

* Scan
* UpdateItem
* UpdateTable
* DeleteTable
* BatchGetItem

I also have very a limited test suite; I will expand as I can. Feel free to fork, add, and submit a pull request.

* * *

Eric Silverberg, March 2012
