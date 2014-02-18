helpers do
  def list_tables(args)
    tables = AWS_REDIS.smembers "tables"
    content_type "application/x-amz-json-1.0"  
    {"TableNames" => tables, 
      "LastEvaluatedTableName" => nil}.to_json
  end
  
  def delete_table(args)
    halt 500 unless args['TableName']

    table_name = args["TableName"]
    key_schema = get_key_schema(table_name)

    keys = AWS_REDIS.keys "tables.#{args['TableName']}.*"    
    AWS_REDIS.del *keys if keys.length > 0
    AWS_REDIS.srem "tables", table_name

    {:Table => 
        {:CreationDateTime => (Time.now.to_i * 1000),        
         :ItemCount => 0,
         :KeySchema => key_schema,
        :ProvisionedThroughput => {
          :LastIncreaseDateTime => (Time.now.to_i * 1000),
          :LastDecreaseDateTime => (Time.now.to_i * 1000),
          :ReadCapacityUnits => 10,
          :WriteCapacityUnits => 10},
        :TableName => table_name,
        :TableStatus => "DELETING"
        }
    }.to_json   
  end
  
  def get_key_schema(table)
    
    hashkey_json = AWS_REDIS.get "tables.#{table}.hashkey"
    rangekey_json = AWS_REDIS.get "tables.#{table}.rangekey"
    
    result = {}
    if hashkey_json
      hashkey = JSON.parse(hashkey_json)
      result[:HashKeyElement] = 
        {:AttributeName => hashkey["AttributeName"], :AttributeType => "S"}
    end
    if rangekey_json
      rangekey = JSON.parse(rangekey_json)
      result[:RangeKeyElement] = 
        {:AttributeName => rangekey["AttributeName"], :AttributeType => "N"}
    end
    
    result
  end
  
  def describe_table(args)
    table_name = args["TableName"]
    key_schema = get_key_schema(table_name)
    halt 404 unless key_schema and key_schema.keys.length > 0
    {:Table => 
        {:CreationDateTime => (Time.now.to_i * 1000),        
         :ItemCount => 0,
         :KeySchema => key_schema,
        :ProvisionedThroughput => {
          :LastIncreaseDateTime => (Time.now.to_i * 1000),
          :LastDecreaseDateTime => (Time.now.to_i * 1000),
          :ReadCapacityUnits => 10,
          :WriteCapacityUnits => 10},
        :TableName => table_name,
        :TableSizeBytes => 1,
        :TableStatus => "ACTIVE"
        }
    }.to_json   
  end
  
  def create_table(args)
    
    halt 500, 'no table name' unless args['TableName']
    halt 500, 'no key schema' unless args['KeySchema']
    halt 500, 'no provisioned throughput' unless args['ProvisionedThroughput']
    halt 500, 'already created' if AWS_REDIS.sismember("tables", args['TableName'])

    AWS_REDIS.sadd "tables", args['TableName']
    AWS_REDIS.set "tables.#{args['TableName']}.auto_incr", 0
    
    if args.has_key?('LocalSecondaryIndexes')
      args['LocalSecondaryIndexes'].each do |lsi|
        index_name = lsi['IndexName']
        AWS_REDIS.sadd "tables.#{args['TableName']}.secondary_indexes", lsi.to_json
      end
    end
    
    if args['KeySchema'].class == Array
      args['KeySchema'].each do |ks|
        
        key_defn = args['AttributeDefinitions'].select{|a| a["AttributeName"] == ks["AttributeName"]}.first
        halt 500 unless key_defn
        
        if ks["KeyType"] == "HASH"
          AWS_REDIS.set "tables.#{args['TableName']}.hashkey", key_defn.to_json
        elsif ks["KeyType"] == "RANGE"
          AWS_REDIS.set "tables.#{args['TableName']}.rangekey", key_defn.to_json
        end
      end
    else
      args['KeySchema'].each do |k,v|
        case k
        when "HashKeyElement"
          AWS_REDIS.set "tables.#{args['TableName']}.hashkey", v.to_json
        when "RangeKeyElement"
          AWS_REDIS.set "tables.#{args['TableName']}.rangekey", v.to_json
        end
      end
    end
        
    return {
      :TableDescription => { 
        :CreationDateTime => (Time.now.to_i * 1000),
        :KeySchema => args['KeySchema'],
        :ProvisionedThroughput => {:ReadsPerSecond => args['ProvisionedThroughput']['ReadsPerSecond'], 
          :WritesPerSecond => args['ProvisionedThroughput']['WritesPerSecond']},
        :TableName => args['TableName'],
        :TableStatus => "CREATING"}
      }.to_json
  end
  
  def update_item(args)
    halt 500, 'no table name' unless args['TableName']
    
    record_value = nil
    record_id = get_record_id(args)
    if record_id
      record_value = JSON.parse(AWS_REDIS.get "tables.#{args['TableName']}.#{record_id}")
      args["AttributeUpdates"].each do |key,update|
        if update["Action"] == "ADD"
          if update["Value"].has_key?("N")
            increment_amount = update["Value"]["N"].to_i

            if record_value.has_key?(key)
              if record_value[key].has_key?("N")
                record_value[key]["N"] = record_value[key]["N"].to_i + increment_amount
              else
                halt 500, "Incorrect type"
              end
            else # it's new, so add it
              record_value[key] = update["Value"]
            end #record_value
          elsif update["Value"].has_key?("S")
            record_value[key] = update["Value"]
          end
        elsif update["Action"] == "DELETE"
          record_value.delete(key)
        end
      end

      AWS_REDIS.set "tables.#{args['TableName']}.#{record_id}", record_value.to_json      
    end

    {:Attributes => record_value, :ConsumedCapacityUnits => 1}.to_json
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

    if args["Item"][hashkey["AttributeName"]].has_key?("S")
      hashkey_value = args["Item"][hashkey["AttributeName"]]["S"]
    else
      hashkey_value = BigDecimal(args["Item"][hashkey["AttributeName"]]["N"])
    end
    
    if (args.has_key?('Expected') and args['Expected'].has_key?('Name') and 
        args['Expected']['Name'].has_key?('Exists') and args['Expected']['Name']['Exists'] == false)
      if AWS_REDIS.hexists "tables.#{args['TableName']}.hashkey_index", hashkey_value
        halt 400, {"__type" => "com.amazonaws.dynamodb.v20111205#ConditionalCheckFailedException", :message => "The conditional request failed"}.to_json
      end
    end
    
    halt 500 unless hashkey_value    
    
    record_id = AWS_REDIS.incr "tables.#{args['TableName']}.auto_incr"
    AWS_REDIS.lpush "tables.#{args['TableName']}.items", record_id
    AWS_REDIS.set "tables.#{args['TableName']}.#{record_id}", args["Item"].to_json
    AWS_REDIS.hset "tables.#{args['TableName']}.hashkey_index", hashkey_value, record_id
    
    if rangekey
      rangekey_value = get_rangekey_value(args["Item"][rangekey["AttributeName"]])
      AWS_REDIS.hset "tables.#{args['TableName']}.hashkey_index.#{hashkey_value}", rangekey_value, record_id
    end
    
    # setup secondary indexes
    secondary_indexes = AWS_REDIS.smembers "tables.#{args['TableName']}.secondary_indexes"
    secondary_indexes.each do |raw|
      lsi = JSON.parse(raw)
      index_name = lsi['IndexName']
      hashkey_value = nil
      rangekey_value = nil
      
      lsi['KeySchema'].each do |attrs|
        attr_name = attrs["AttributeName"]
        key_type = attrs["KeyType"]
        
        if key_type == "HASH"
          if args["Item"][attrs["AttributeName"]].has_key?("S")
            hashkey_value = args["Item"][attrs["AttributeName"]]["S"]
          else
            hashkey_value = BigDecimal(args["Item"][attrs["AttributeName"]]["N"])
          end
        else
          if args["Item"][attrs["AttributeName"]].has_key?("S")
            rangekey_value = args["Item"][attrs["AttributeName"]]["S"]
          else
            rangekey_value = BigDecimal(args["Item"][attrs["AttributeName"]]["N"])
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
    
    return {
      :Attributes => args["Item"],
      :WritesUsed => 1
    }.to_json
  end
  
  def get_record_id(args)
    hashkey_value = nil
    rangekey_value = nil
    
    if !args['Key'].has_key?("HashKeyElement")
      hashkey_json = AWS_REDIS.get "tables.#{args['TableName']}.hashkey"
      rangekey_json = AWS_REDIS.get "tables.#{args['TableName']}.rangekey"   

      hashkey = JSON.parse(hashkey_json) if hashkey_json
      rangekey = JSON.parse(rangekey_json) if rangekey_json
      
      if args["Key"][hashkey["AttributeName"]].has_key?("S")
        hashkey_value = args["Key"][hashkey["AttributeName"]]["S"]
      else
        hashkey_value = BigDecimal(args["Key"][hashkey["AttributeName"]]["N"])
      end

      if args["Key"][rangekey["AttributeName"]].has_key?("S")
        rangekey_value = args["Key"][rangekey["AttributeName"]]["S"]
      else
        rangekey_value = BigDecimal(args["Key"][rangekey["AttributeName"]]["N"])
      end
    else
      halt 500 unless args['Key'].has_key?("HashKeyElement")
    
      if args['Key']['HashKeyElement'].has_key?('S')
        hashkey_value = args['Key']['HashKeyElement']['S']
      else
        hashkey_value = BigDecimal(args['Key']['HashKeyElement']['N'])
      end
    
      if args['Key'].has_key?('RangeKeyElement')
        if args['Key']['RangeKeyElement'].has_key?('S')
          rangekey_value = args['Key']['RangeKeyElement']['S']
        else
          rangekey_value = BigDecimal(args['Key']['RangeKeyElement']['N'])
        end
      end
    end
    
    raise "no hashkey value" unless hashkey_value
    
    record_id = nil
    if rangekey_value.nil?
      record_id = AWS_REDIS.hget("tables.#{args['TableName']}.hashkey_index", hashkey_value)
    else
      record_id = AWS_REDIS.hget("tables.#{args['TableName']}.hashkey_index.#{hashkey_value}", rangekey_value)
    end
    
    return record_id
  end
  
  def get_item(args)
    halt 500, 'no table name' unless args['TableName']
    halt 500, 'no key' unless args['Key']
    
    record_id = get_record_id(args)
    record_value = record_id ? JSON.parse(AWS_REDIS.get "tables.#{args['TableName']}.#{record_id}") : nil
    
    return record_value ? {:Item => record_value, :ReadsUsed => 1}.to_json : {}.to_json
  end
  
  def convert_rangekey_value(rangekey_value, rangekey_type)
    if rangekey_type == "N"
      return BigDecimal(rangekey_value)
    else
      return rangekey_value
    end
  end
  
  def get_rangekey_value(rangekey)
    if rangekey.has_key?("N")
      rangekey_value = BigDecimal(rangekey["N"])
    else
      rangekey_value = rangekey["S"]
    end    
    
    return rangekey_value
  end
  
  def query(args)    
    halt 500, 'no table name' unless args['TableName']
    halt 500, 'no hash key value' unless (args['HashKeyValue'] or args['IndexName'])
    
    scan_index_forward = args.has_key?("ScanIndexForward") ? args["ScanIndexForward"] : true
    key_conditions = nil
    
    if args.has_key?("IndexName")
      key_conditions = args["KeyConditions"]
    elsif args["HashKeyValue"].first.first == "N"
      hashkey_value = BigDecimal(args["HashKeyValue"].first.last)
    else
      hashkey_value = args["HashKeyValue"].first.last
    end
    
    exclusive_start_key = nil
    last_evaluated_key = nil

    hashkey_name = JSON::parse((AWS_REDIS.get "tables.#{args['TableName']}.hashkey"))['AttributeName']
    
    rangekey_obj = JSON::parse((AWS_REDIS.get "tables.#{args['TableName']}.rangekey"))
    rangekey_name = rangekey_obj['AttributeName']
    rangekey_type = rangekey_obj['AttributeType']
    
    exclusive_start_hashkey_value = exclusive_start_rangekey_value = nil
    if not args['ExclusiveStartKey'].nil?
      exclusive_start_hashkey_value = args['ExclusiveStartKey']['HashKeyElement'].values.last
      exclusive_start_rangekey_value = args['ExclusiveStartKey']['RangeKeyElement'].values.last
    end
    
    if key_conditions # we are doing a new-style query
      # remove the hash-key from the conditions, leaving only the key on which we are querying
      query_key = key_conditions.keys.select{|k| k != 'hk' }.first
      rangekey = key_conditions[query_key]
      
      hashkey_value = get_rangekey_value(key_conditions['hk']['AttributeValueList'].first)
      rangekeys = AWS_REDIS.keys "tables.#{args['TableName']}.secondary_index.#{args['IndexName']}.#{hashkey_value}/*"

      if rangekey['ComparisonOperator'] == "GE"
        rangekey_value = get_rangekey_value(rangekey["AttributeValueList"].first)
        rangekey_type = rangekey["AttributeValueList"].first.keys.first # "N" or "S"
        
        valid_rangekeys = rangekeys.select{|rk| 
            (convert_rangekey_value(rk.split("/").last, rangekey_type) <=> rangekey_value) >= 0
          }.sort{|a,b| 
            convert_rangekey_value(a.split("/").last, rangekey_type) <=> convert_rangekey_value(b.split("/").last, rangekey_type)
          }
      elsif rangekey['ComparisonOperator'] == "LE"
        rangekey_value = get_rangekey_value(rangekey["AttributeValueList"].first)
        rangekey_type = rangekey["AttributeValueList"].first.keys.first # "N" or "S"
        
        valid_rangekeys = rangekeys.select{|rk| 
            (convert_rangekey_value(rk.split("/").last, rangekey_type) <=> rangekey_value) <= 0
          }.sort{|a,b| 
            convert_rangekey_value(a.split("/").last, rangekey_type) <=> convert_rangekey_value(b.split("/").last, rangekey_type)
          }
      end
      
      if valid_rangekeys.length > 0
        record_ids = []
        valid_rangekeys.each do |rk|
          record_ids += AWS_REDIS.smembers(rk)
        end
        record_keys = record_ids.map{|record_id| "tables.#{args['TableName']}.#{record_id}"}
        items = record_keys.length > 0 ? (AWS_REDIS.mget *record_keys).map{|i| JSON.parse(i)} : []
      else
        items = []
      end
            
    elsif args.has_key?("RangeKeyCondition")
      rangekeys = AWS_REDIS.hkeys "tables.#{args['TableName']}.hashkey_index.#{hashkey_value}"
      rangekey_json = AWS_REDIS.get "tables.#{args['TableName']}.rangekey"
      
      if args["RangeKeyCondition"]["ComparisonOperator"] == "LT"
        rangekey_value = get_rangekey_value(args["RangeKeyCondition"]["AttributeValueList"].first)
        valid_rangekeys = rangekeys.map{|rk| convert_rangekey_value(rk, rangekey_type)}.select{|rk| (rk <=> rangekey_value) == -1}.sort
      elsif args["RangeKeyCondition"]["ComparisonOperator"] == "GT"
        rangekey_value = get_rangekey_value(args["RangeKeyCondition"]["AttributeValueList"].first)
        valid_rangekeys = rangekeys.map{|rk| convert_rangekey_value(rk, rangekey_type)}.select{|rk| (rk <=> rangekey_value) == +1}.sort
      elsif args["RangeKeyCondition"]["ComparisonOperator"] == "GE"
        rangekey_value = get_rangekey_value(args["RangeKeyCondition"]["AttributeValueList"].first)
        valid_rangekeys = rangekeys.map{|rk| convert_rangekey_value(rk, rangekey_type)}.select{|rk| (rk <=> rangekey_value) >= 0}.sort
      elsif args["RangeKeyCondition"]["ComparisonOperator"] == "LE"
        rangekey_value = get_rangekey_value(args["RangeKeyCondition"]["AttributeValueList"].first)
        valid_rangekeys = rangekeys.map{|rk| convert_rangekey_value(rk, rangekey_type)}.select{|rk| (rk <=> rangekey_value) <= 0}.sort
      elsif args["RangeKeyCondition"]["ComparisonOperator"] == "EQ"
        rangekey_value = get_rangekey_value(args["RangeKeyCondition"]["AttributeValueList"].first)
        valid_rangekeys = rangekeys.map{|rk| convert_rangekey_value(rk, rangekey_type)}.select{|rk| (rk <=> rangekey_value) == 0}
      elsif args["RangeKeyCondition"]["ComparisonOperator"] == "BETWEEN"
        first_rangekey_value = get_rangekey_value(args["RangeKeyCondition"]["AttributeValueList"].first)
        last_rangekey_value = get_rangekey_value(args["RangeKeyCondition"]["AttributeValueList"].last)
        valid_rangekeys = rangekeys.map{|rk| convert_rangekey_value(rk, rangekey_type)}.select{|rk| (rk <=> first_rangekey_value) >= 0 and (rk <=> last_rangekey_value) <= 0}
      end
      
      record_ids = valid_rangekeys.length > 0 ? (AWS_REDIS.hmget("tables.#{args['TableName']}.hashkey_index.#{hashkey_value}", *valid_rangekeys)).map{|record_id|
        "tables.#{args['TableName']}.#{record_id}"
        } : []
      items = record_ids.length > 0 ? (AWS_REDIS.mget *record_ids).map{|i| JSON.parse(i)} : []
    else
      record_ids = AWS_REDIS.hvals("tables.#{args['TableName']}.hashkey_index.#{hashkey_value}")
      keys = record_ids.map{|item|
        "tables.#{args['TableName']}.#{item}"
        }
      items = keys.length > 0 ? AWS_REDIS.mget(*keys).map{|i| JSON.parse(i)} : []
    end
    
    if exclusive_start_hashkey_value and exclusive_start_rangekey_value

      # So we move through it correctly depending on asc or desc
      if scan_index_forward
        items.reverse!
      end
      
      idx = 0
      items.each do |item|
        idx += 1
        hashkey_value_dict = item[hashkey_name]
        rangekey_value_dict = item[rangekey_name]
        hashkey_value_type = hashkey_value_dict.keys.first
        rangekey_value_type = rangekey_value_dict.keys.first

        hashkey_value = hashkey_value_dict.values.first
        rangekey_value = rangekey_value_dict.values.first

        if exclusive_start_hashkey_value == hashkey_value and
           exclusive_start_rangekey_value == rangekey_value
           break  
        end  
      end
      
      items = items[idx..-1]
    end
    
    if scan_index_forward and rangekey_name
      items.sort!{|a,b|
        get_rangekey_value(a[rangekey_name]) <=> get_rangekey_value(b[rangekey_name])
      }
    elsif not scan_index_forward and rangekey_name
      items.sort!{|a,b|
        get_rangekey_value(b[rangekey_name]) <=> get_rangekey_value(a[rangekey_name])
      }
    end
    
    if items and items.count > 0
      hashkey_value_dict = items.last[hashkey_name]
      rangekey_value_dict = items.last[rangekey_name]
      hashkey_value_type = hashkey_value_dict.keys.first
      rangekey_value_type = rangekey_value_dict.keys.first
      
      hashkey_value = hashkey_value_dict.values.first
      rangekey_value = rangekey_value_dict.values.first

      last_evaluated_key = {
        :HashKeyElement => {hashkey_value_type => hashkey_value},
        :RangeKeyElement => {rangekey_value_type => rangekey_value},
      }
    end    

    result = {:Count => items.length, :Items => items, :ReadsUsed => 1}
    if last_evaluated_key
      result[:LastEvaluatedKey] = last_evaluated_key
    end
    
    return result.to_json
  end
  
  def delete_item(args)
    halt 500, 'no table name' unless args['TableName']
    halt 500, 'no key' unless args['Key']
    
    if args["Key"]["HashKeyElement"].has_key?("N")
      hashkey_value = BigDecimal(args['Key']['HashKeyElement']['N'])
    else
      hashkey_value = args['Key']['HashKeyElement']['S']
    end
    
    if args["Key"].has_key?("RangeKeyElement")
      rangekey_value = get_rangekey_value(args['Key']['RangeKeyElement'])
    end
    
    if hashkey_value and rangekey_value
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
      item = JSON.parse(AWS_REDIS.get "tables.#{args['TableName']}.#{record_id}")
      AWS_REDIS.del "tables.#{args['TableName']}.#{record_id}"
    end   
     
    return {"Item" => item, "ReadsUsed" => 1}.to_json
  end
  
  def batch_write_item(args)
    items = []
    responses = {}
    
    args['RequestItems'].each do |k,v|
      table_name = k
      requests = v
      requests.each do |request|
        request.each do |k2, v2|
          case k2
          when "DeleteRequest"
            delete_item({'TableName' => table_name, 'Key' => v2['Key']})
            responses[table_name] = {"ConsumedCapacityUnits" => 1}
          end
        end
      end
    end
    
    return {:Responses => responses, :UnprocessedItems => []}.to_json    
  end
  
end

post '/dynamodb/?' do
  req = Rack::Request.new(env)
  
  amz_target = nil
  if env["HTTP_X_AMZ_TARGET"]
    amz_target = env["HTTP_X_AMZ_TARGET"].split(".").last
  elsif env["x-amz-target"]
    amz_target = env["x-amz-target"].split(".").last
  end
  
  if env["REQUEST_METHOD"] == "POST"
    args = JSON::parse(env['rack.input'].read)
  else
    args = env['rack.request.form_hash']
  end
  
  content_type "application/x-amz-json-1.0"  
  case amz_target
  when "CreateTable"
    return create_table(args)
  when "DeleteTable"
    return delete_table(args)
  when "DescribeTable"
    return describe_table(args)
  when "PutItem"
    return put_item(args)
  when "GetItem"
    return get_item(args)
  when "DeleteItem"
    return delete_item(args)
  when "UpdateItem"
    return update_item(args)
  when "Query"
    return query(args)
  when "ListTables"
    return list_tables(args)
  when "BatchWriteItem"
    return batch_write_item(args)
  else
    halt 500, "unknown command #{req.inspect}"
  end
end