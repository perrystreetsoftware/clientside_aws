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


License
=======
MIT License (http://en.wikipedia.org/wiki/MIT_License). Some parts of this code were adapted from the aws-sdk project, which can be found at: https://github.com/amazonwebservices/aws-sdk-for-ruby and is itself licensed under the Apache 2.0 license.

Copyright (C) 2012 Perry Street Software, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.