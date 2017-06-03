$LOAD_PATH << "#{File.dirname(__FILE__)}/../"

require 'aws-sdk'
require 'aws-sdk-v1'
require 'spec/spec_helper'

describe 'EC2 Spec' do
  include Rack::Test::Methods
  def app
    Sinatra::Application
  end

  def build_ec2_args(security_group:, remote_addr:, mask:, port:)
    args = { group_id: security_group }
    if remote_addr =~ /\:/ && remote_addr.length >= 16
      args[:ip_permissions] = [{
        from_port: port,
        to_port: port,
        ip_protocol: 'tcp',
        ipv_6_ranges: [{ cidr_ipv_6: "#{remote_addr}/#{mask}" }]
      }]
    else
      args[:ip_permissions] = [{
        from_port: port,
        to_port: port,
        ip_protocol: 'tcp',
        ip_ranges: [{ cidr_ip: "#{remote_addr}/#{mask}" }]
      }]
    end

    args
  end

  it 'should create ingress groups' do
    ec2 = Aws::EC2::Client.new

    args = build_ec2_args(
      security_group: 'sg-foo',
      remote_addr: '192.168.99.100',
      mask: 24,
      port: 443
    )
    ec2.authorize_security_group_ingress(args)

    desc = ec2.describe_security_groups(
      group_ids: ['sg-foo']
    )
    expect(desc.security_groups.length).to eq 1
    count_of_ip_ranges = \
      desc&.security_groups&.first&.ip_permissions&.first&.ip_ranges&.length
    expect(count_of_ip_ranges).to eq 1

    first_ip_range = \
      desc&.security_groups&.first&.ip_permissions&.first&.ip_ranges&.first
    expect(first_ip_range.cidr_ip).to eq '192.168.99.0/24'

    args = build_ec2_args(
      security_group: 'sg-foo',
      remote_addr: '192.168.99.0',
      mask: 24,
      port: 443
    )

    ec2.revoke_security_group_ingress(args)

    desc = ec2.describe_security_groups(
      group_ids: ['sg-foo']
    )

    expect(desc.security_groups.first.ip_permissions.first).to be nil
  end

  it 'should create ingress groups on different ports' do
    ec2 = Aws::EC2::Client.new

    args = build_ec2_args(
      security_group: 'sg-foo2',
      remote_addr: '192.168.99.101',
      mask: 16,
      port: 22
    )

    ec2.authorize_security_group_ingress(args)

    args = build_ec2_args(
      security_group: 'sg-foo2',
      remote_addr: '10.0.0.1',
      mask: 32,
      port: 22
    )

    ec2.authorize_security_group_ingress(args)

    desc = ec2.describe_security_groups(
      group_ids: ['sg-foo2']
    )

    ip_ranges = \
      desc.security_groups.first.ip_permissions.first.ip_ranges.map(&:cidr_ip)

    expect(ip_ranges.include?('10.0.0.1/32')).to be true
    expect(ip_ranges.include?('192.168.0.0/16')).to be true

    args = build_ec2_args(
      security_group: 'sg-foo2',
      remote_addr: '10.0.0.1',
      mask: 32,
      port: 22
    )

    ec2.revoke_security_group_ingress(args)

    desc = ec2.describe_security_groups(
      group_ids: ['sg-foo2']
    )

    ip_ranges = \
      desc.security_groups.first.ip_permissions.first.ip_ranges.map(&:cidr_ip)

    expect(ip_ranges.include?('10.0.0.1/32')).to be false
    expect(ip_ranges.include?('192.168.0.0/16')).to be true

    args = build_ec2_args(
      security_group: 'sg-foo2',
      remote_addr: '192.168.0.0',
      mask: 16,
      port: 22
    )

    ec2.revoke_security_group_ingress(args)

    desc = ec2.describe_security_groups(
      group_ids: ['sg-foo2']
    )

    ip_ranges = \
      desc.security_groups.first.ip_permissions
    expect(ip_ranges.length.zero?).to be true
  end
end
