# Features

- Write code on a plane: Interact with AWS services like S3, SQS and DynamoDb, without Internet access
- No more tedious configuration of mocked responses in your unit tests
- Save time and money by avoiding the need for a test account in AWS where you upload S3 files and interact with DynamoDb databases along with other developers on your team
- Instantly restore your development and test environments to known good states

# Installation

There are two parts to installation: including the `clientside_aws` gem in your application, and running a docker container that mocks the AWS services.

## Container configuration

From OSX, type:

    gem install clientside_aws

This will install a gem and a script that lets you build the Clientside AWS docker image. Once the `clientside_aws` gem is installed locally on OSX, you will need to build the Clientside AWS docker image. Run:

    clientside_aws_build

Once that docker image is built, it will be available for you to manually launch or include in `docker-compose.yml` files.

    $ docker images
    REPOSITORY                           TAG                 IMAGE ID            CREATED             SIZE
    clientside_aws                       latest              fec78caf81be        just now            881MB
    mysql                                5.7                 e27c7a14671f        20 months ago       361MB
    redis                                latest              93a08017b97e        22 months ago       151MB
    memcached                            latest              355142d48ea3        22 months ago       132MB

To manually launch a docker container running Clientside AWS, run:

    docker run -d --rm -p <YOUR_PREFERRED_PORT>:4567 --name clientside_aws clientside_aws:latest

Or, run:

    clientside_aws_run

To include in a `docker-compose.yml` file, see [the example](/examples/dockerized/docker-compose.yml).

## Application configuration

In your gemfile:

    gem 'clientside_aws', require: 'clientside_aws'

Then, at the top of your application where you are configuring global services, type:

    config = { region: 'us-mockregion-1',
               access_key_id: '...',
               secret_access_key: '...' }

    Aws.config.update(config)
    AWS.config(config)

You can see that you do not need to specify a valid access_key_id nor secret_access_key, but you must set the region to be `us-mockregion-1` -- this is how Clientside AWS identifies and redirects requests to AWS services.

Clientside AWS is also capable of mocking requests from the v1 and v2 versions of the [aws-sdk-ruby](https://github.com/aws/aws-sdk-ruby) gem. It is not yet tested with v3.

See [the example](/examples/dockerized/app/index.rb) for how to configure Clientside AWS in your application.

# Classic development approach

![Classic approach diagram](/examples/documentation/classic_model.png)

In the classic approach to development, you would install application services like mysql, redis and memcached locally on OSX. You would then install the ruby runtime, with tools like [rvm](https://rvm.io/). With luck, you wouldn't encounter OSX-specific bugs, [like this one](https://blog.phusion.nl/2017/10/13/why-ruby-app-servers-break-on-macos-high-sierra-and-what-can-be-done-about-it/).

When you needed to interact with AWS services, you would either use [WebMock](https://github.com/bblimke/webmock) to provide a known response to outbound requests (probably in your rspec tests), and for development you would create a test account on AWS that had empty S3 buckets and DynamoDb databases. This account might have been shared with other developers, and could (over time) get polluted with development data. It was flushed infrequently, if ever. It also cost money, even if a nominal amount.

# Clientside AWS approach

With Clientside AWS, you have two approaches to configuring your application services: Partial or Full Docker.

## Partial docker

![Partial docker diagram](/examples/documentation/partial_docker.png)

With the partial docker approach, you continue to install runtime environments locally on OSX like [rvm](https://rvm.io/), but you also install [Docker for Mac](https://www.docker.com/docker-mac), on which you launch a container running Clientside AWS. You then `require clientside_aws` in your application which redirects AWS requests to the container. You also may consider running other services, like mysql, memcached and redis, inside a docker container.

See [this example](/examples/local/) for how to configure a partial docker development approach.

## Full docker

![Full docker diagram](/examples/documentation/full_docker.png)

With the full docker approach, you do 100% of your web application development from within Docker. Your OSX laptop only need to have a web browser, a text editor, and docker installed (and if you are doing mobile development, Xcode/Android Studio).

When developing with the full docker approach, your application runtime it itself running in a container. However, because your application code will be changing and churning constantly, it doesn't make sense to run a COPY command and seal it up, as one normally does with docker containers that you are shipping to other places. Instead, you mount your local OSX filesystem into an Ubuntu container, on which you have also installed the ruby runtime. You also execute an interactive bash script on that container, so you can easily do things like stop and restart your web server. This container creates network links between itself and your other services, including Clientside AWS, mysql, redis, memcached, postgres, etc.

See [this example](/examples/dockerized/) for how to figure a full docker development approach.

TODO
=======
* Add support for V3 of the aws-sdk gem


License
=======
[MIT License](http://en.wikipedia.org/wiki/MIT_License). Some parts of this code were adapted from the [aws-sdk project](https://github.com/aws/aws-sdk-core-ruby), which is itself licensed under the Apache 2.0 license.

Copyright (C) 2012-2017 Perry Street Software, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
