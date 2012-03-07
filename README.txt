To run this code, you will need ruby, sinatra, and the json and redis rubygems. I also use the sinatra/reloader gem to aid in development, but it is not necessary.

You will also need redis-server installed locally

Edit spec_helper.rb and configure the REDIS_PATH variable at the top to point to the install location of redis-server

Then, from the command line, run:

  ruby spec/dyndb_spec.rb

That will run the unit tests against this code.

To launch this code standalone, run:

  ruby index.rb

That will launch sinatra and run the code on localhost:4567

-- 

Eric Silverberg
silver@cs.stanford.edu
December 2011
