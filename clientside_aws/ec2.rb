helpers do
  def authorize_security_group_ingress(params)
    port_info = { ToPort: params['ToPort'],
                  FromPort: params['FromPort'],
                  GroupId: params['GroupId'],
                  IpProtocol: params['IpProtocol'],
                  CidrIp: params['CidrIp'] }
    AWS_REDIS.sadd("ingress:#{params['GroupId']}", port_info.to_json)
  end

  def revoke_security_group_ingress(params)
    AWS_REDIS.smembers("ingress:#{params['GroupId']}").each do |member_raw|
      member = JSON.parse(member_raw)
      if member['CidrIp'] == params['CidrIp']
        AWS_REDIS.srem "ingress:#{params['GroupId']}", member_raw
        break
      end
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
            if AWS_REDIS.scard("ingress:#{group_id}").positive?
              xml.item do
                xml.tag!(:ipProtocol, 'TCP')
                xml.tag!(:fromPort, 443)
                xml.tag!(:toPort, 443)
                xml.tag!(:groups, nil)
                xml.ipRanges do
                  ingress_permissions = AWS_REDIS.smembers("ingress:#{group_id}")
                  ingress_permissions.each do |raw|
                    permission = JSON.parse(raw)

                    xml.item do
                      xml.tag!(:cidrIp, permission['CidrIp'])
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
