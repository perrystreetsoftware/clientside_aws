helpers do
  def list_tables(_args)
    tables = AWS_REDIS.smembers 'tables'
    content_type 'application/x-amz-json-1.0'
    { 'TableNames' => tables,
      'LastEvaluatedTableName' => nil }.to_json
  end

  def delete_table(args)
    halt 500 unless args['TableName']

    table_name = args['TableName']
    key_schema = get_key_schema(table_name)

    keys = AWS_REDIS.keys "tables.#{args['TableName']}.*"
    AWS_REDIS.del *keys unless keys.empty?
    AWS_REDIS.srem 'tables', table_name

    { Table:         { CreationDateTime: (Time.now.to_i * 1000),
                       ItemCount: 0,
                       KeySchema: key_schema,
                       ProvisionedThroughput: {
                         LastIncreaseDateTime: (Time.now.to_i * 1000),
                         LastDecreaseDateTime: (Time.now.to_i * 1000),
                         ReadCapacityUnits: 10,
                         WriteCapacityUnits: 10
                       },
                       TableName: table_name,
                       TableStatus: 'DELETING' } }.to_json
  end

  def clear_from_secondary_indices(table_name, record_id)
    # Note the keys operation is a table scan that is brutally inefficient
    secondary_indexes = AWS_REDIS.smembers "tables.#{table_name}.secondary_indexes"
    secondary_indexes.each do |si_raw|
      si = JSON.parse(si_raw)
      keys = AWS_REDIS.keys "tables.#{table_name}.secondary_index.#{si['IndexName']}.*"
      keys.each do |key|
        AWS_REDIS.srem key, record_id
      end
    end
  end

  def get_key_schema(table)
    hashkey_json = AWS_REDIS.get "tables.#{table}.hashkey"
    rangekey_json = AWS_REDIS.get "tables.#{table}.rangekey"

    result = {}
    if hashkey_json
      hashkey = JSON.parse(hashkey_json)
      result[:HashKeyElement] =
        { AttributeName: hashkey['AttributeName'], AttributeType: 'S' }
    end
    if rangekey_json
      rangekey = JSON.parse(rangekey_json)
      result[:RangeKeyElement] =
        { AttributeName: rangekey['AttributeName'], AttributeType: 'N' }
    end

    result
  end

  def describe_table(args)
    table_name = args['TableName']
    key_schema = get_key_schema(table_name)
    halt 404 unless key_schema && !key_schema.keys.empty?
    { Table:         { CreationDateTime: (Time.now.to_i * 1000),
                       ItemCount: 0,
                       KeySchema: key_schema,
                       ProvisionedThroughput: {
                         LastIncreaseDateTime: (Time.now.to_i * 1000),
                         LastDecreaseDateTime: (Time.now.to_i * 1000),
                         ReadCapacityUnits: 10,
                         WriteCapacityUnits: 10
                       },
                       TableName: table_name,
                       TableSizeBytes: 1,
                       TableStatus: 'ACTIVE' } }.to_json
  end

  def create_table(args)
    halt 500, 'no table name' unless args['TableName']
    halt 500, 'no key schema' unless args['KeySchema']
    halt 500, 'no provisioned throughput' unless args['ProvisionedThroughput']
    halt 500, 'already created' if AWS_REDIS.sismember('tables', args['TableName'])

    AWS_REDIS.sadd 'tables', args['TableName']
    AWS_REDIS.set "tables.#{args['TableName']}.auto_incr", 0

    if args.key?('LocalSecondaryIndexes')
      args['LocalSecondaryIndexes'].each do |si|
        index_name = si['IndexName']
        AWS_REDIS.sadd "tables.#{args['TableName']}.secondary_indexes", si.to_json
      end
    end

    if args.key?('GlobalSecondaryIndexes')
      args['GlobalSecondaryIndexes'].each do |si|
        index_name = si['IndexName']
        AWS_REDIS.sadd "tables.#{args['TableName']}.secondary_indexes", si.to_json
      end
    end

    if args['KeySchema'].class == Array
      args['KeySchema'].each do |ks|
        key_defn = args['AttributeDefinitions'].select { |a| a['AttributeName'] == ks['AttributeName'] }.first
        halt 500 unless key_defn

        if ks['KeyType'] == 'HASH'
          AWS_REDIS.set "tables.#{args['TableName']}.hashkey", key_defn.to_json
        elsif ks['KeyType'] == 'RANGE'
          AWS_REDIS.set "tables.#{args['TableName']}.rangekey", key_defn.to_json
        end
      end
    else
      args['KeySchema'].each do |k, v|
        case k
        when 'HashKeyElement'
          AWS_REDIS.set "tables.#{args['TableName']}.hashkey", v.to_json
        when 'RangeKeyElement'
          AWS_REDIS.set "tables.#{args['TableName']}.rangekey", v.to_json
        end
      end
    end

    {
      TableDescription: {
        CreationDateTime: (Time.now.to_i * 1000),
        KeySchema: args['KeySchema'],
        ProvisionedThroughput: { ReadsPerSecond: args['ProvisionedThroughput']['ReadsPerSecond'],
                                 WritesPerSecond: args['ProvisionedThroughput']['WritesPerSecond'] },
        TableName: args['TableName'],
        TableStatus: 'CREATING'
      }
    }.to_json
  end

  def update_item(args)
    halt 500, 'no table name' unless args['TableName']

    record_value = nil
    record_id = get_record_id(args)

    # No record, probably doing an add
    if record_id.nil?

      # Figure out the range key
      rangekey_json = AWS_REDIS.get "tables.#{args['TableName']}.rangekey"
      rangekey = JSON.parse(rangekey_json) if rangekey_json

      # Add the range key and give a default value of zero
      attribute_name = rangekey['AttributeName']
      attribute_type = rangekey['AttributeType']
      item_key = args['Key'].clone
      item_key[attribute_name] = { attribute_type.to_s => 0 }
      put_item('TableName' => args['TableName'], 'Item' => item_key)

      record_id = get_record_id(args)
    end

    if record_id
      record_value = JSON.parse(AWS_REDIS.get("tables.#{args['TableName']}.#{record_id}"))
      args['AttributeUpdates'].each do |key, update|
        if update['Action'] == 'ADD'
          if update['Value'].key?('N')
            increment_amount = update['Value']['N'].to_i

            if record_value.key?(key)
              halt 500, 'Incorrect type' unless record_value[key].key?('N')
              record_value[key]['N'] = record_value[key]['N'].to_i + increment_amount
            else # it's new, so add it
              record_value[key] = update['Value']
            end # record_value
          elsif update['Value'].key?('S')
            record_value[key] = update['Value']
          end
        elsif update['Action'] == 'DELETE'
          record_value.delete(key)
        end
      end

      AWS_REDIS.set "tables.#{args['TableName']}.#{record_id}",
                    record_value.to_json
    end

    { Attributes: record_value, ConsumedCapacityUnits: 1 }.to_json
  end

  def put_item(args)
    halt 500, 'no table name' unless args['TableName']
    halt 500, 'no item' unless args['Item']

    hashkey = rangekey = nil
    hashkey_json = AWS_REDIS.get "tables.#{args['TableName']}.hashkey"
    rangekey_json = AWS_REDIS.get "tables.#{args['TableName']}.rangekey"

    hashkey = JSON.parse(hashkey_json) if hashkey_json
    rangekey = JSON.parse(rangekey_json) if rangekey_json

    halt 500 if hashkey.nil?

    if args['Item'][hashkey['AttributeName']].key?('S')
      hashkey_value = args['Item'][hashkey['AttributeName']]['S']
    else
      hashkey_value = BigDecimal(args['Item'][hashkey['AttributeName']]['N'])
    end

    if args.key?('Expected') && args['Expected'].key?('Name') &&
       args['Expected']['Name'].key?('Exists') && args['Expected']['Name']['Exists'] == false
      if AWS_REDIS.hexists "tables.#{args['TableName']}.hashkey_index", hashkey_value
        halt 400, { '__type' => 'com.amazonaws.dynamodb.v20111205#ConditionalCheckFailedException', :message => 'The conditional request failed' }.to_json
      end
    end

    halt 500 unless hashkey_value

    if rangekey
      rangekey_value = get_rangekey_value(args['Item'][rangekey['AttributeName']])

      if AWS_REDIS.hexists("tables.#{args['TableName']}.hashkey_index.#{hashkey_value}", rangekey_value)
        record_id = AWS_REDIS.hget "tables.#{args['TableName']}.hashkey_index.#{hashkey_value}", rangekey_value
        clear_from_secondary_indices(args['TableName'], record_id)
      else
        record_id = AWS_REDIS.incr "tables.#{args['TableName']}.auto_incr"
        AWS_REDIS.hset "tables.#{args['TableName']}.hashkey_index.#{hashkey_value}", rangekey_value, record_id
        AWS_REDIS.lpush "tables.#{args['TableName']}.items", record_id
        AWS_REDIS.hset "tables.#{args['TableName']}.hashkey_index", hashkey_value, record_id
      end
    else
      record_id = AWS_REDIS.incr "tables.#{args['TableName']}.auto_incr"
      AWS_REDIS.lpush "tables.#{args['TableName']}.items", record_id
      AWS_REDIS.hset "tables.#{args['TableName']}.hashkey_index", hashkey_value, record_id
    end

    AWS_REDIS.set "tables.#{args['TableName']}.#{record_id}", args['Item'].to_json

    # setup secondary indexes
    secondary_indexes = AWS_REDIS.smembers "tables.#{args['TableName']}.secondary_indexes"
    secondary_indexes.each do |raw|
      lsi = JSON.parse(raw)
      index_name = lsi['IndexName']
      hashkey_value = nil
      rangekey_value = nil

      lsi['KeySchema'].each do |attrs|
        attr_name = attrs['AttributeName']
        key_type = attrs['KeyType']

        if key_type == 'HASH'
          if args['Item'][attrs['AttributeName']].key?('S')
            hashkey_value = args['Item'][attrs['AttributeName']]['S']
          else
            hashkey_value = BigDecimal(args['Item'][attrs['AttributeName']]['N'])
          end
        else
          if args['Item'][attrs['AttributeName']].key?('S')
            rangekey_value = args['Item'][attrs['AttributeName']]['S']
          else
            rangekey_value = BigDecimal(args['Item'][attrs['AttributeName']]['N'])
          end
        end
      end

      # Secondary indexes store sets, not hmaps
      # H => 1, R => 2, TS => 3
      # H => 1, R => 3, TS => 3
      # This means the secondary index on TS should have two records, {H => 1, R => 2} and {H => 1, R => 3}
      # Storing as a hmap on H, TS would overwrite

      AWS_REDIS.sadd "tables.#{args['TableName']}.secondary_index.#{index_name}.#{hashkey_value}/#{rangekey_value}", record_id
    end

    {
      Attributes: args['Item'],
      WritesUsed: 1
    }.to_json
  end

  def get_record_id(args)
    hashkey_value = nil
    rangekey_value = nil

    if !args['Key'].key?('HashKeyElement')
      hashkey_json = AWS_REDIS.get "tables.#{args['TableName']}.hashkey"
      rangekey_json = AWS_REDIS.get "tables.#{args['TableName']}.rangekey"

      return nil unless hashkey_json

      hashkey = JSON.parse(hashkey_json) if hashkey_json
      rangekey = JSON.parse(rangekey_json) if rangekey_json

      if args['Key'][hashkey['AttributeName']].key?('S')
        hashkey_value = args['Key'][hashkey['AttributeName']]['S']
      else
        hashkey_value = BigDecimal(args['Key'][hashkey['AttributeName']]['N'])
      end

      if rangekey
        if args['Key'][rangekey['AttributeName']].nil?
          rangekey_value = nil
        elsif args['Key'][rangekey['AttributeName']].key?('S')
          rangekey_value = args['Key'][rangekey['AttributeName']]['S']
        else
          rangekey_value = BigDecimal(args['Key'][rangekey['AttributeName']]['N'])
        end
      end
    else
      halt 500 unless args['Key'].key?('HashKeyElement')

      if args['Key']['HashKeyElement'].key?('S')
        hashkey_value = args['Key']['HashKeyElement']['S']
      else
        hashkey_value = BigDecimal(args['Key']['HashKeyElement']['N'])
      end

      if args['Key'].key?('RangeKeyElement')
        if args['Key']['RangeKeyElement'].key?('S')
          rangekey_value = args['Key']['RangeKeyElement']['S']
        else
          rangekey_value = BigDecimal(args['Key']['RangeKeyElement']['N'])
        end
      end
    end

    raise 'no hashkey value' unless hashkey_value

    record_id = nil
    if rangekey_value.nil?
      record_id = AWS_REDIS.hget("tables.#{args['TableName']}.hashkey_index", hashkey_value)
    else
      record_id = AWS_REDIS.hget("tables.#{args['TableName']}.hashkey_index.#{hashkey_value}", rangekey_value)
    end

    record_id
  end

  def get_item(args)
    halt 500, 'no table name' unless args['TableName']
    halt 500, 'no key' unless args['Key']

    record_id = get_record_id(args)
    record_value = record_id ? JSON.parse(AWS_REDIS.get("tables.#{args['TableName']}.#{record_id}")) : nil

    record_value ? { Item: record_value, ReadsUsed: 1 }.to_json : {}.to_json
  end

  def convert_rangekey_value(rangekey_value, rangekey_type)
    if rangekey_type == 'N'
      return BigDecimal(rangekey_value)
    else
      return rangekey_value
    end
  end

  def get_rangekey_value(rangekey)
    rangekey_value = if rangekey.key?('N')
                       BigDecimal(rangekey['N'])
                     else
                       rangekey['S']
                     end

    rangekey_value
  end

  def query(args)
    halt 500, 'no table name' \
      unless args['TableName']
    halt 500, 'no hash key value' \
      unless args['HashKeyValue'] ||
             args['IndexName'] ||
             args['KeyConditions']

    key_conditions = args['KeyConditions']
    limit = args.key?('Limit') ? args['Limit'] : nil
    scan_index_forward = if args.key?('ScanIndexForward')
                           args['ScanIndexForward']
                         else
                           true
                         end

    # exclusive_start_key = nil
    last_evaluated_key = nil

    hashkey_obj = \
      JSON.parse((AWS_REDIS.get "tables.#{args['TableName']}.hashkey"))
    hashkey_name = hashkey_obj['AttributeName']
    # hashkey_type = hashkey_obj['AttributeType']

    # V1 api sends HashKeyValue directly
    if args.key?('HashKeyValue') && args['HashKeyValue'].key?('N')
      hashkey_value = BigDecimal(args['HashKeyValue']['N'])
    elsif !key_conditions.nil?
      # V2 api sends hash key value inside a keyconditions hash
      hashkey_value = \
        get_rangekey_value( \
          key_conditions[hashkey_name]['AttributeValueList'].first
        )
    else
      raise 'Unknown hash key value'
    end

    rangekey_obj = \
      JSON.parse(AWS_REDIS.get("tables.#{args['TableName']}.rangekey"))
    rangekey_name = rangekey_obj['AttributeName']
    rangekey_type = rangekey_obj['AttributeType']

    exclusive_start_hashkey_value = nil
    exclusive_start_rangekey_value = nil

    unless args['ExclusiveStartKey'].nil?
      exclusive_start_hashkey_value = \
        args['ExclusiveStartKey']['HashKeyElement'].values.last
      exclusive_start_rangekey_value = \
        args['ExclusiveStartKey']['RangeKeyElement'].values.last
    end

    if args.key?('IndexName') # we are doing a new-style query
      # remove the hash-key from the conditions,
      # leaving only the key on which we are querying
      rangekey_name = key_conditions.keys.select { |k| k != hashkey_name }.first
      rangekey = key_conditions[rangekey_name]

      rangekeys = AWS_REDIS.keys "tables.#{args['TableName']}.secondary_index.#{args['IndexName']}.#{hashkey_value}/*"

      if rangekey['ComparisonOperator'] == 'GE'
        rangekey_value = get_rangekey_value(rangekey['AttributeValueList'].first)
        rangekey_type = rangekey['AttributeValueList'].first.keys.first # "N" or "S"

        valid_rangekeys = rangekeys.select do |rk|
                            (convert_rangekey_value(rk.split('/').last, rangekey_type) <=> rangekey_value) >= 0
                          end.sort do |a, b|
          convert_rangekey_value(a.split('/').last, rangekey_type) <=> convert_rangekey_value(b.split('/').last, rangekey_type)
        end
      elsif rangekey['ComparisonOperator'] == 'LE' || rangekey['ComparisonOperator'] == 'LT'
        rangekey_value = get_rangekey_value(rangekey['AttributeValueList'].first)
        rangekey_type = rangekey['AttributeValueList'].first.keys.first # "N" or "S"

        valid_rangekeys = rangekeys.select do |rk|
                            if rangekey['ComparisonOperator'] == 'LE'
                              (convert_rangekey_value(rk.split('/').last, rangekey_type) <=> rangekey_value) <= 0
                            else
                              (convert_rangekey_value(rk.split('/').last, rangekey_type) <=> rangekey_value) < 0
                            end
                          end.sort do |a, b|
          convert_rangekey_value(a.split('/').last, rangekey_type) <=> convert_rangekey_value(b.split('/').last, rangekey_type)
        end
      end

      if !valid_rangekeys.empty?
        record_ids = []
        valid_rangekeys.each do |rk|
          record_ids += AWS_REDIS.smembers(rk)
        end
        record_keys = record_ids.map { |record_id| "tables.#{args['TableName']}.#{record_id}" }
        items = !record_keys.empty? ? (AWS_REDIS.mget *record_keys).map { |i| JSON.parse(i) } : []
      else
        items = []
      end

    elsif (args.key?('KeyConditions') && args['KeyConditions'][rangekey_name]) ||
          args.key?('RangeKeyCondition')

      if args['KeyConditions']
        # New API v2: comes in as { table_name: {KeyCondtions}}
        key_conditions = args['KeyConditions']
      elsif args['RangeKeyCondition']
        # Old API v1: comes in as { KeyConditions }
        # So lets map it to the API v2
        key_conditions = {}
        key_conditions[rangekey_name] = args['RangeKeyCondition']
      end

      rangekeys = AWS_REDIS.hkeys "tables.#{args['TableName']}.hashkey_index.#{hashkey_value}"

      rangekey_value = \
        get_rangekey_value( \
          key_conditions[rangekey_name]['AttributeValueList'].first
        )
      last_rangekey_value = \
        get_rangekey_value( \
          key_conditions[rangekey_name]['AttributeValueList'].last
        )

      case key_conditions[rangekey_name]['ComparisonOperator']
      when 'LT'
        comparator = lambda do |rk|
          (rk <=> rangekey_value) == -1
        end
      when 'GT'
        comparator = lambda do |rk|
          (rk <=> rangekey_value) == +1
        end
      when 'GE'
        comparator = lambda do |rk|
          (rk <=> rangekey_value) >= 0
        end
      when 'LE'
        comparator = lambda do |rk|
          (rk <=> rangekey_value) <= 0
        end
      when 'EQ'
        comparator = lambda do |rk|
          (rk <=> rangekey_value).zero?
        end
      when 'BETWEEN'
        comparator = lambda do |rk|
          (rk <=> rangekey_value) >= 0 && (rk <=> last_rangekey_value) <= 0
        end
      end

      valid_rangekeys = \
        rangekeys.map do |rk|
          convert_rangekey_value(rk, rangekey_type)
        end.select(&comparator).sort

      record_ids = []

      unless valid_rangekeys.empty?
        record_ids = \
          AWS_REDIS.hmget("tables.#{args['TableName']}.hashkey_index." \
                          "#{hashkey_value}", *valid_rangekeys).map do |rid|
            "tables.#{args['TableName']}.#{rid}"
          end
      end

      items = []
      unless record_ids.empty?
        items = (AWS_REDIS.mget record_ids).map do |i|
          JSON.parse(i)
        end
      end
    else
      record_ids = AWS_REDIS.hvals("tables.#{args['TableName']}." \
                                   "hashkey_index.#{hashkey_value}")
      keys = record_ids.map do |item|
        "tables.#{args['TableName']}.#{item}"
      end
      items = !keys.empty? ? AWS_REDIS.mget(*keys).map { |i| JSON.parse(i) } : []
    end

    if exclusive_start_hashkey_value && exclusive_start_rangekey_value

      # So we move through it correctly depending on asc or desc
      items.reverse! if scan_index_forward

      idx = 0
      items.each do |item|
        idx += 1
        hashkey_value_dict = item[hashkey_name]
        rangekey_value_dict = item[rangekey_name]
        hashkey_value_type = hashkey_value_dict.keys.first
        rangekey_value_type = rangekey_value_dict.keys.first

        hashkey_value = hashkey_value_dict.values.first
        rangekey_value = rangekey_value_dict.values.first

        if exclusive_start_hashkey_value == hashkey_value &&
           exclusive_start_rangekey_value == rangekey_value
          break
        end
      end

      items = items[idx..-1]
    end

    if scan_index_forward && rangekey_name
      items.sort! do |a, b|
        get_rangekey_value(a[rangekey_name]) <=> get_rangekey_value(b[rangekey_name])
      end
    elsif !scan_index_forward && rangekey_name
      items.sort! do |a, b|
        get_rangekey_value(b[rangekey_name]) <=> get_rangekey_value(a[rangekey_name])
      end
    end

    if items && items.count > 0 && limit && limit < items.count
      hashkey_value_dict = items[limit][hashkey_name]
      rangekey_value_dict = items[limit][rangekey_name]
      hashkey_value_type = hashkey_value_dict.keys.first
      rangekey_value_type = rangekey_value_dict.keys.first

      hashkey_value = hashkey_value_dict.values.first
      rangekey_value = rangekey_value_dict.values.first

      last_evaluated_key = {
        HashKeyElement: { hashkey_value_type => hashkey_value },
        RangeKeyElement: { rangekey_value_type => rangekey_value }
      }
      items = items[0...limit] # apply limit
    end

    result = { Count: items.length, Items: items, ReadsUsed: 1 }

    # This should not be the last key returned, but instead the next key you would
    # have returned but didn't.

    result[:LastEvaluatedKey] = last_evaluated_key if last_evaluated_key

    result.to_json
  end

  def delete_item(args)
    halt 500, 'no table name' unless args['TableName']
    halt 500, 'no key' unless args['Key']

    if args['Key'].key?('HashKeyElement')
      if args['Key']['HashKeyElement'].key?('N')
        hashkey_value = BigDecimal(args['Key']['HashKeyElement']['N'])
      else
        hashkey_value = args['Key']['HashKeyElement']['S']
      end
    else
      hashkey_raw = AWS_REDIS.get "tables.#{args['TableName']}.hashkey"
      hashkey = JSON.parse(hashkey_raw)
      if hashkey['AttributeType'] == 'N'
        hashkey_value = BigDecimal(args['Key'][hashkey['AttributeName']][hashkey['AttributeType']])
      else
        hashkey_value = args['Key'][hashkey['AttributeName']][hashkey['AttributeType']]
      end
    end

    rangekey_value = nil
    if args['Key'].key?('RangeKeyElement')
      rangekey_value = get_rangekey_value(args['Key']['RangeKeyElement'])
    else
      rangekey_raw = AWS_REDIS.get "tables.#{args['TableName']}.rangekey"
      if rangekey_raw
        rangekey = JSON.parse(rangekey_raw)
        if rangekey['AttributeType'] == 'N'
          rangekey_value = BigDecimal(args['Key'][rangekey['AttributeName']][rangekey['AttributeType']])
        else
          rangekey_value = args['Key'][rangekey['AttributeName']][rangekey['AttributeType']]
        end
      end
    end

    if hashkey_value && rangekey_value
      record_id = AWS_REDIS.hget "tables.#{args['TableName']}.hashkey_index.#{hashkey_value}", rangekey_value
    else
      record_id = AWS_REDIS.hget "tables.#{args['TableName']}.hashkey_index", hashkey_value
    end

    item = nil
    if record_id
      AWS_REDIS.hdel "tables.#{args['TableName']}.hashkey_index", hashkey_value
      if rangekey_value
        AWS_REDIS.hdel "tables.#{args['TableName']}.hashkey_index.#{hashkey_value}", rangekey_value
      end
      item = JSON.parse(AWS_REDIS.get("tables.#{args['TableName']}.#{record_id}"))
      AWS_REDIS.del "tables.#{args['TableName']}.#{record_id}"

      clear_from_secondary_indices(args['TableName'], record_id)
    end

    { 'Item' => item, 'ReadsUsed' => 1 }.to_json
  end

  def batch_write_item(args)
    items = []
    responses = {}

    args['RequestItems'].each do |k, v|
      table_name = k
      requests = v
      requests.each do |request|
        request.each do |k2, v2|
          case k2
          when 'DeleteRequest'
            delete_item('TableName' => table_name, 'Key' => v2['Key'])
            responses[table_name] = { 'ConsumedCapacityUnits' => 1 }
          end
        end
      end
    end

    { Responses: responses, UnprocessedItems: [] }.to_json
  end
end

post %r{/dynamodb\.([\w-]+?)\.amazonaws\.com/?} do
  req = Rack::Request.new(env)

  amz_target = nil

  %w(HTTP_X_AMZ_TARGET x-amz-target X-Amz-Target).each do |key|
    next unless env.key?(key)
    amz_target = env[key].split('.').last
    break
  end

  args = if env['REQUEST_METHOD'] == 'POST'
           JSON.parse(env['rack.input'].read)
         else
           env['rack.request.form_hash']
         end

  content_type 'application/x-amz-json-1.0'
  case amz_target
  when 'CreateTable'
    return create_table(args)
  when 'DeleteTable'
    return delete_table(args)
  when 'DescribeTable'
    return describe_table(args)
  when 'PutItem'
    return put_item(args)
  when 'GetItem'
    return get_item(args)
  when 'DeleteItem'
    return delete_item(args)
  when 'UpdateItem'
    return update_item(args)
  when 'Query'
    return query(args)
  when 'ListTables'
    return list_tables(args)
  when 'BatchWriteItem'
    return batch_write_item(args)
  else
    halt 500, "unknown command #{req.inspect}"
  end
end
