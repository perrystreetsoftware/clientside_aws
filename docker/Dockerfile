FROM phusion/baseimage:0.9.15
MAINTAINER Eric Silverberg

# Set correct environment variables.
ENV HOME /root

# Regenerate SSH host keys. baseimage-docker does not contain any, so you
# have to do that yourself. You may also comment out this instruction; the
# init system will auto-generate one during boot.
RUN /etc/my_init.d/00_regen_ssh_host_keys.sh

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]

RUN mkdir /mnt/redis

RUN apt-add-repository ppa:brightbox/ruby-ng -y
RUN apt-get update && apt-get install -y ruby2.1 ruby2.1-dev git-core build-essential
RUN apt-get install -y wget curl

RUN cd /opt ; wget "http://download.redis.io/releases/redis-2.8.17.tar.gz"
RUN cd /opt ; gunzip redis-2.8.17.tar.gz ; tar -xvf redis-2.8.17.tar
RUN cd /opt/redis-2.8.17 ; ./configure ; make ; sudo make install

# Install for testing ffmpeg stuff
RUN apt-get install -y libav-tools

RUN mkdir /etc/service/redis-server
ADD redis-server-run /etc/service/redis-server/run
RUN chmod 755 /etc/service/redis-server/run

# Add redis conf file
RUN mkdir /etc/redis
RUN cd /opt/redis-2.8.17 ; cat redis.conf | sed "s/dir \.\//dir \/mnt\/redis\//" > /etc/redis/redis.conf

# Now, fetch clientside aws
RUN gem install bundler
RUN cd /opt ; git clone https://github.com/perrystreetsoftware/clientside_aws.git
RUN cd /opt/clientside_aws ; bundle install

RUN mkdir /etc/service/clientside-aws
ADD clientside-aws-run /etc/service/clientside-aws/run
RUN chmod 755 /etc/service/clientside-aws/run

EXPOSE 4567

# Clean up APT when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*


