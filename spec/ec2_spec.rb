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
      ip_protocol: 'tcp'
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
      ip_protocol: 'tcp'
    )

    desc = ec2.describe_security_groups(
      group_ids: ['sg-foo']
    )

    expect(desc.security_groups.first.ip_permissions.first).to be nil
  end

  it 'should create ingress groups on different ports' do
    ec2 = Aws::EC2::Client.new

    ec2.authorize_security_group_ingress(
      group_id: 'sg-foo2',
      cidr_ip: '192.168.99.101/16',
      from_port: 22,
      to_port: 22,
      ip_protocol: 'tcp'
    )

    ec2.authorize_security_group_ingress(
      group_id: 'sg-foo2',
      cidr_ip: '10.0.0.1/32',
      from_port: 22,
      to_port: 22,
      ip_protocol: 'tcp'
    )

    desc = ec2.describe_security_groups(
      group_ids: ['sg-foo2']
    )

    ip_ranges = \
      desc.security_groups.first.ip_permissions.first.ip_ranges.map { |r| r.cidr_ip }

    expect(ip_ranges.include?('10.0.0.1/32')).to be true
    expect(ip_ranges.include?('192.168.99.101/16')).to be true

    ec2.revoke_security_group_ingress(
      group_id: 'sg-foo2',
      cidr_ip: '10.0.0.1/32',
      from_port: 22,
      to_port: 22,
      ip_protocol: 'tcp'
    )

    desc = ec2.describe_security_groups(
      group_ids: ['sg-foo2']
    )

    ip_ranges = \
      desc.security_groups.first.ip_permissions.first.ip_ranges.map { |r| r.cidr_ip }

    expect(ip_ranges.include?('10.0.0.1/32')).to be false
    expect(ip_ranges.include?('192.168.99.101/16')).to be true

    ec2.revoke_security_group_ingress(
      group_id: 'sg-foo2',
      cidr_ip: '192.168.99.101/16',
      from_port: 22,
      to_port: 22,
      ip_protocol: 'tcp'
    )

    desc = ec2.describe_security_groups(
      group_ids: ['sg-foo2']
    )

    ip_ranges = \
      desc.security_groups.first.ip_permissions
    expect(ip_ranges.length.zero?).to be true
  end
end
