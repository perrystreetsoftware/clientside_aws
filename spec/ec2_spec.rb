$LOAD_PATH << "#{File.dirname(__FILE__)}/../"

require 'aws-sdk'
require 'aws-sdk-v1'
require 'spec/spec_helper'

describe 'EC2 Spec' do
  include Rack::Test::Methods
  def app
    Sinatra::Application
  end

  it 'should create ingress groups' do
    ec2 = Aws::EC2::Client.new

    ec2.authorize_security_group_ingress(
      group_id: 'sg-foo',
      cidr_ip: '192.168.99.100/24',
      from_port: 443,
      to_port: 443,
      ip_protocol: 'TCP'
    )

    desc = ec2.describe_security_groups(
      group_ids: ['sg-foo']
    )
    expect(desc.security_groups.length).to eq 1
    count_of_ip_ranges = \
      desc&.security_groups&.first&.ip_permissions&.first&.ip_ranges&.length
    expect(count_of_ip_ranges).to eq 1

    first_ip_range = \
      desc&.security_groups&.first&.ip_permissions&.first&.ip_ranges&.first
    expect(first_ip_range.cidr_ip).to eq '192.168.99.100/24'

    ec2.revoke_security_group_ingress(
      group_id: 'sg-foo',
      cidr_ip: '192.168.99.100/24',
      from_port: 443,
      to_port: 443,
      ip_protocol: 'TCP'
    )

    desc = ec2.describe_security_groups(
      group_ids: ['sg-foo']
    )

    first_ip_range = \
      desc.security_groups.first.ip_permissions.first.ip_ranges.first

    expect(first_ip_range).to be nil
  end
end
