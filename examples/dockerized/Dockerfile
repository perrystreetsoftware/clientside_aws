FROM phusion/baseimage:0.9.22
ENV HOME /root

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]

# Install ruby
RUN apt-add-repository ppa:brightbox/ruby-ng -y
RUN apt-get update && apt-get install -y ruby2.4 ruby2.4-dev git-core build-essential zlib1g-dev
RUN apt-get install -y wget curl

# Install app code
RUN gem install bundler
RUN cd /opt
COPY app/ /opt/app/
RUN cd /opt/app ; bundle install

# Use runit to start the app
RUN mkdir /etc/service/app
ADD app-run /etc/service/app/run
RUN chmod 755 /etc/service/app/run

EXPOSE 4567
WORKDIR /opt/app
