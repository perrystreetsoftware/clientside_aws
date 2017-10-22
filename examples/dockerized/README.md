# Installation

To run this example, type

    docker-compose up -d

Once it has launched, run

    docker ps

This should show you something like this:

    CONTAINER ID        IMAGE                     COMMAND                  CREATED             STATUS              PORTS                                              NAMES
    ec9815828e64        clientside_aws_test_app   "/sbin/my_init"          3 seconds ago       Up 1 second         0.0.0.0:32847->4567/tcp                            clientside_aws_test_app
    b19233b502f8        clientside_aws:latest     "/sbin/my_init"          5 seconds ago       Up 2 seconds        0.0.0.0:32846->4567/tcp                            clientside_aws_test_aws

You can see that the `clientside_aws_test_app` container is running on port `32847`. Thus, from your local web browser, type in:

    http://localhost:32847/

And you should see the example running there.
