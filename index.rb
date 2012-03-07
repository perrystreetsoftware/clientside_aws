require 'rubygems'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'json'
require 'redis'

helpers do
  def list_tables(args)
    tables = REDIS.smembers "tables"
    content_type "application/x-amz-json-1.0"  
    {"TableNames" => tables, 
      "LastEvaluatedTableName" => nil}.to_json
  end
    
  def get_key_schema(table)
    
    hashkey_json = REDIS.get "tables.#{table}.hashkey"
    rangekey_json = REDIS.get "tables.#{table}.rangekey"
    
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
    halt 500, 'already created' if REDIS.sismember("tables", args['TableName'])

    REDIS.sadd "tables", args['TableName']
    REDIS.set "tables.#{args['TableName']}.auto_incr", 0
    
    args['KeySchema'].each do |k,v|
      case k
      when "HashKeyElement"
        REDIS.set "tables.#{args['TableName']}.hashkey", v.to_json
      when "RangeKeyElement"
        REDIS.set "tables.#{args['TableName']}.rangekey", v.to_json
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
  
  def put_item(args)
    halt 500, 'no table name' unless args['TableName']
    halt 500, 'no item' unless args['Item']
    
    hashkey = rangekey = nil
    hashkey_json = REDIS.get "tables.#{args['TableName']}.hashkey"
    rangekey_json = REDIS.get "tables.#{args['TableName']}.rangekey"   
    
    hashkey = JSON.parse(hashkey_json) if hashkey_json
    rangekey = JSON.parse(rangekey_json) if rangekey_json
    
    if args["Item"][hashkey["AttributeName"]].has_key?("S")
      hashkey_value = args["Item"][hashkey["AttributeName"]]["S"]
    else
      hashkey_value = BigDecimal(args["Item"][hashkey["AttributeName"]]["N"])
    end
    halt 500 unless hashkey_value    
    
    record_id = REDIS.incr "tables.#{args['TableName']}.auto_incr"
    REDIS.lpush "tables.#{args['TableName']}.items", record_id
    REDIS.set "tables.#{args['TableName']}.#{record_id}", args["Item"].to_json
    REDIS.hset "tables.#{args['TableName']}.hashkey_index", hashkey_value, record_id
    
    if rangekey
      rangekey_value = BigDecimal(args["Item"][rangekey["AttributeName"]]["N"])
      REDIS.hset "tables.#{args['TableName']}.hashkey_index.#{hashkey_value}", rangekey_value, record_id
      REDIS.zadd "tables.#{args['TableName']}.rangekey_index.#{hashkey_value}", rangekey_value, record_id
    end
    
    return {
      :Attributes => args["Item"],
      :WritesUsed => 1
    }.to_json
  end
  
  def get_item(args)
    halt 500, 'no table name' unless args['TableName']
    halt 500, 'no key' unless args['Key']
    
    hashkey_value = nil
    rangekey_value = nil
    
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
    
    raise "no hashkey value" unless hashkey_value
    
    record_id = nil
    if rangekey_value.nil?
      record_id = REDIS.hget("tables.#{args['TableName']}.hashkey_index", hashkey_value)
    else
      record_id = REDIS.hget("tables.#{args['TableName']}.hashkey_index.#{hashkey_value}", rangekey_value)
    end
    
    record_value = record_id ? JSON.parse(REDIS.get "tables.#{args['TableName']}.#{record_id}") : nil
    
    return {:Item => record_value, :ReadsUsed => 1}.to_json
  end
    
  def query(args)
    halt 500, 'no table name' unless args['TableName']
    halt 500, 'no hash key value' unless args['HashKeyValue']
    halt 500, 'no range key condition' unless args['RangeKeyCondition']

    if args["HashKeyValue"].first.first == "N"
      hashkey_value = BigDecimal(args["HashKeyValue"].first.last)
    else
      hashkey_value = args["HashKeyValue"].first.last
    end
    
    exclusive_start_key = nil
    last_evaluated_key = nil
    hashkey_name = JSON::parse((REDIS.get "tables.#{args['TableName']}.hashkey"))['AttributeName']
    rangekey_name = JSON::parse((REDIS.get "tables.#{args['TableName']}.rangekey"))['AttributeName']
    
    exclusive_start_hashkey_value = exclusive_start_rangekey_value = nil
    if not args['ExclusiveStartKey'].nil?
      exclusive_start_hashkey_value = args['ExclusiveStartKey']['HashKeyElement'].values.last
      exclusive_start_rangekey_value = args['ExclusiveStartKey']['RangeKeyElement'].values.last
    end
    
    
    if args["RangeKeyCondition"]["ComparisonOperator"] == "LT"
      rangekey_value = BigDecimal(args["RangeKeyCondition"]["AttributeValueList"].first["N"])
      record_ids = (REDIS.zrangebyscore("tables.#{args['TableName']}.rangekey_index.#{hashkey_value}", 0, rangekey_value)).map{|record_id|
          "tables.#{args['TableName']}.#{record_id}"
        }
      items = record_ids.length > 0 ? (REDIS.mget *record_ids).map{|i| JSON.parse(i)} : []
    elsif args["RangeKeyCondition"]["ComparisonOperator"] == "EQ"
      rangekey_value = BigDecimal(args["RangeKeyCondition"]["AttributeValueList"].first["N"])
      record_ids = (REDIS.zrangebyscore("tables.#{args['TableName']}.rangekey_index.#{hashkey_value}", rangekey_value, rangekey_value)).map{|record_id|
          "tables.#{args['TableName']}.#{record_id}"
        }
      items = record_ids.length > 0 ? (REDIS.mget *record_ids).map{|i| JSON.parse(i)} : []
    elsif args["RangeKeyCondition"]["ComparisonOperator"] == "BETWEEN"
      first_rangekey_value = BigDecimal(args["RangeKeyCondition"]["AttributeValueList"].first["N"])
      last_rangekey_value = BigDecimal(args["RangeKeyCondition"]["AttributeValueList"].last["N"])
      record_ids = (REDIS.zrangebyscore("tables.#{args['TableName']}.rangekey_index.#{hashkey_value}", first_rangekey_value, last_rangekey_value)).map{|record_id|
          "tables.#{args['TableName']}.#{record_id}"
        }
      items = record_ids.length > 0 ? (REDIS.mget *record_ids).map{|i| JSON.parse(i)} : []
    end
    
    if exclusive_start_hashkey_value and exclusive_start_rangekey_value
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
    
    if items and items.count > 0
      hashkey_value_dict = items.last[hashkey_name]
      rangekey_value_dict = items.last[rangekey_name]
      hashkey_value_type = hashkey_value_dict.keys.first
      rangekey_value_type = rangekey_value_dict.keys.first
      
      hashkey_value = hashkey_value_dict.values.first
      rangekey_value = rangekey_value_dict.values.first

      last_evaluated_key = {
        :HashKeyElement => {hashkey_value_type, hashkey_value},
        :RangeKeyElement => {rangekey_value_type, rangekey_value},
      }
    end    

    return {:Count => items.length, :Items => items, :ReadsUsed => 1,
      :LastEvaluatedKey => last_evaluated_key}.to_json
  end
  
  def delete_item(args)
    halt 500, 'no table name' unless args['TableName']
    halt 500, 'no key' unless args['Key']
    
    if args["Key"]["HashKeyElement"].has_key?("N")
      hashkey_value = BigDecimal(args['Key']['HashKeyElement']['N'])
    else
      hashkey_value = BigDecimal(args['Key']['HashKeyElement']['S'])
    end
    
    rangekey_value = nil
    if args['Key']['RangeKeyElement'].has_key?("N")
      rangekey_value = BigDecimal(args['Key']['RangeKeyElement']['N'])
    end
    
    if hashkey_value and rangekey_value
      record_id = REDIS.hget "tables.#{args['TableName']}.hashkey_index.#{hashkey_value}", rangekey_value      
    else
      record_id = REDIS.hget "tables.#{args['TableName']}.hashkey_index", hashkey_value      
    end

    item = nil
    if record_id    
      REDIS.hdel "tables.#{args['TableName']}.hashkey_index", hashkey_value
      if rangekey_value
        REDIS.hdel "tables.#{args['TableName']}.hashkey_index.#{hashkey_value}", rangekey_value
        REDIS.zrem "tables.#{args['TableName']}.rangekey_index.#{hashkey_value}", record_id
      end
      item = JSON.parse(REDIS.get "tables.#{args['TableName']}.#{record_id}")
      REDIS.del "tables.#{args['TableName']}.#{record_id}"
    end   
     
    return {"Item" => item, "ReadsUsed" => 1}.to_json
  end
  
end

configure :test do
  REDIS = Redis.new(:host => "localhost", :port => 6380, :timeout => 10)
end

configure :development do
  REDIS = Redis.new
end

DYNAMODB_PREFIX = "DynamoDBv20110924"

get '/' do
  "hello"
end

post '/' do
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
  when "DescribeTable"
    return describe_table(args)
  when "PutItem"
    return put_item(args)
  when "GetItem"
    return get_item(args)
  when "DeleteItem"
    return delete_item(args)
  when "Query"
    return query(args)
  when "ListTables"
    return list_tables(args)
  else
    halt 500, "unknown command #{req.inspect}"
  end
end