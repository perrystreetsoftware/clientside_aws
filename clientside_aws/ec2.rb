require 'ipaddr'

helpers do
  def hkey_from_params(params)
    "#{params['IpPermissions.1.IpProtocol']}:" \
    "#{params['IpPermissions.1.FromPort']}:" \
    "#{params['IpPermissions.1.ToPort']}"
  end

  def authorize_security_group_ingress(params)
    hkey = hkey_from_params(params)
    existing = AWS_REDIS.hget("ingress:#{params['GroupId']}",
                              hkey)
    value = existing ? JSON.parse(existing).to_set : Set.new
    ip_addr = IPAddr.new(params['IpPermissions.1.IpRanges.1.CidrIp'])
    mask = params['IpPermissions.1.IpRanges.1.CidrIp'].split('/').last
    # Interpret the mask, so 10.0.0.1/24 converts to 10.0.0.0/24
    value << "#{ip_addr}/#{mask}"

    AWS_REDIS.hset("ingress:#{params['GroupId']}",
                   hkey,
                   value.to_a.to_json)
  end

  def revoke_security_group_ingress(params)
    hkey = hkey_from_params(params)
    value = AWS_REDIS.hget("ingress:#{params['GroupId']}", hkey)

    return unless value

    new_value = JSON.parse(value).reject do |r|
      r == params['IpPermissions.1.IpRanges.1.CidrIp']
    end

    if new_value.length.positive?
      AWS_REDIS.hset("ingress:#{params['GroupId']}", hkey, new_value.to_json)
    else
      AWS_REDIS.hdel("ingress:#{params['GroupId']}", hkey)
    end
  end

  def describe_security_groups
    group_id = params['GroupId.1']

    xml = Builder::XmlMarkup.new
    xml.instruct!
    xmlns = 'http://ec2.amazonaws.com/doc/2016-11-15/'
    xml.DescribeSecurityGroupsResponse(xmlns: xmlns) do
      xml.tag!(:requestId, UUID.new.generate)
      xml.securityGroupInfo do
        xml.item do
          xml.tag!(:ownerId, UUID.new.generate)
          xml.tag!(:groupId, group_id)
          xml.tag!(:groupName, 'group-name')
          xml.tag!(:groupDescription, 'group-description')
          xml.tag!(:vpcId, 'vpc-00000000')
          xml.ipPermissions do
            AWS_REDIS.hkeys("ingress:#{group_id}").each do |protocol_port_tuple|
              xml.item do
                (protocol, from_port, to_port) = protocol_port_tuple.split(':')

                xml.tag!(:ipProtocol, protocol)
                xml.tag!(:fromPort, from_port.to_i)
                xml.tag!(:toPort, to_port.to_i)
                xml.tag!(:groups, nil)

                xml.ipRanges do
                  ingress_permissions = \
                    AWS_REDIS.hget("ingress:#{group_id}", protocol_port_tuple)
                  JSON.parse(ingress_permissions).each do |cidr_ip|
                    xml.item do
                      xml.tag!(:cidrIp, cidr_ip)
                    end
                  end
                end
                xml.tag!(:ipv6Ranges, nil)
                xml.tag!(:prefixListIds, nil)
              end
            end
          end
        end
      end
    end

    content_type :xml
    xml.target!
  end
end

post %r{/ec2(\.(\w+?)\.amazonaws\.com)?/?(.*)} do
  case params[:Action]
  when 'AuthorizeSecurityGroupIngress'
    authorize_security_group_ingress(params)

    200
  when 'RevokeSecurityGroupIngress'
    revoke_security_group_ingress(params)

    200
  when 'DescribeSecurityGroups'
    describe_security_groups
  end
end
