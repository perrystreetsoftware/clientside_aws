FROM phusion/baseimage:0.9.22
MAINTAINER Perry Street Software

# Set correct environment variables.
ENV HOME /root

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]

RUN mkdir /mnt/redis

RUN apt-add-repository ppa:brightbox/ruby-ng -y
RUN apt-get update && apt-get install -y ruby2.4 ruby2.4-dev git-core build-essential zlib1g-dev
RUN apt-get install -y wget curl telnet

RUN cd /opt ; wget "http://download.redis.io/releases/redis-2.8.24.tar.gz"
RUN cd /opt ; gunzip redis-2.8.24.tar.gz ; tar -xvf redis-2.8.24.tar
RUN cd /opt/redis-2.8.24 ; ./configure ; make ; make install

# Install for testing ffmpeg stuff
RUN apt-get install -y libav-tools

RUN mkdir /etc/service/redis-server
ADD docker/redis-server-run /etc/service/redis-server/run
RUN chmod 755 /etc/service/redis-server/run

# Add redis conf file
RUN mkdir /etc/redis
RUN cd /opt/redis-2.8.24 ; cat redis.conf | sed "s/dir \.\//dir \/mnt\/redis\//" > /etc/redis/redis.conf

# Now, fetch clientside aws
RUN gem install bundler -v 1.16.6
RUN cd /opt
COPY . /opt/clientside_aws/
RUN cd /opt/clientside_aws ; bundle install

RUN mkdir /etc/service/clientside-aws
ADD docker/clientside-aws-run /etc/service/clientside-aws/run
RUN chmod 755 /etc/service/clientside-aws/run

EXPOSE 4567

# Clean up APT when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /opt/clientside_aws
