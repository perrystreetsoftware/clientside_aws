$LOAD_PATH << "#{File.dirname(__FILE__)}/../"

require 'spec/spec_helper'

describe 'Profiles Spec' do
  include Rack::Test::Methods

  before(:each) do
    # Clean data after each test so we do not stomp on each other!
    AWS_REDIS.flushall
  end

  def app
    Sinatra::Application
  end

  it 'says hello' do
    get '/'
    expect(last_response).to be_ok
  end

  it 'v1: should handle basic CRUD test' do
    dynamo_db = AWS::DynamoDB.new

    test_table = dynamo_db.tables.create('test1', 1, 1,
                                         hash_key: { creator_id: :number },
                                         range_key: { date: :number })

    expect(dynamo_db.tables.to_a.length).to eq 1
    expect(dynamo_db.tables['test1'].exists?).to be true

    test_table.hash_key = [:creator_id, :number]
    test_table.range_key = [:date, :number]

    now = Time.now.to_f
    test_table.items.put(creator_id: 10, date: now, data1: 'data1')
    expect(test_table.items[10, now].exists?).to be true
    expect(test_table.items[11, now].exists?).to be false

    results = test_table.items.query(hash_value: 10, range_value: (0..(now + 1)))
    expect(results.to_a.length).to eq 1
    expect(results.to_a.first.attributes['creator_id']).to eq 10

    results = test_table.items.query(hash_value: 10, range_value: 0..1)
    expect(results.to_a.length).to eq 0

    results = test_table.items.query(hash_value: 10, range_value: (0..(now + 1)))
    results.to_a.first.attributes.update do |u|
      u.add 'foo' => 'bar'
      u.add 'bar' => 100
    end

    expect(test_table.items[10, now].attributes['foo']).to eq 'bar'
    expect(test_table.items[10, now].attributes['bar']).to eq 100

    test_table.items[10, now].attributes.update do |u|
      u.delete 'foo'
    end

    expect(test_table.items[10, now].attributes['foo']).to be_nil

    item = test_table.items[10, now]
    item.delete
    expect(test_table.items[10, now].exists?).to be false

    test_table.delete
    expect(dynamo_db.tables.to_a.length).to eq 0
  end

  it 'v2: should handle basic CRUD test' do
    dynamo_db = Aws::DynamoDB::Client.new

    dynamo_db.create_table(
      table_name: 'test',
      provisioned_throughput: {
        read_capacity_units: 10,
        write_capacity_units: 10
      },
      attribute_definitions: [{ attribute_name: :creator_id,
                                attribute_type: 'N' },
                              { attribute_name: :date,
                                attribute_type: 'N' }],
      key_schema: [{ attribute_name: :creator_id, key_type: 'HASH' },
                   { attribute_name: :date, key_type: 'RANGE' }]
    )

    expect(dynamo_db.list_tables.table_names.length).to eq 1
    expect(dynamo_db.list_tables.table_names.include?('test')).to be true

    now = Time.now
    dynamo_db.put_item(
      table_name: 'test',
      item: {
        'creator_id' => 10,
        'date' => now.to_f,
        'data1' => 'data1'
      }
    )

    result1 = dynamo_db.get_item(table_name: 'test',
                                 key: { 'creator_id' => 10,
                                        'date' => now.to_f })

    result2 = dynamo_db.get_item(table_name: 'test',
                                 key: { 'creator_id' => 11,
                                        'date' => now.to_f })

    expect(result1.item).not_to be nil
    expect(result2.item).to be nil

    results = dynamo_db.query(
      table_name: 'test',
      scan_index_forward: false,
      key_conditions: { 'creator_id' => { comparison_operator: 'EQ',
                                          attribute_value_list: [10] },
                        'date' => { comparison_operator: 'LT',
                                    attribute_value_list: [(now + 1).to_f] } }
    )

    expect(results.count).to eq 1
    expect(results.items.first['creator_id']).to eq 10

    results = dynamo_db.query(
      table_name: 'test',
      scan_index_forward: true,
      key_conditions: { 'creator_id' => { comparison_operator: 'EQ',
                                          attribute_value_list: [10] },
                        'date' => { comparison_operator: 'LT',
                                    attribute_value_list: [1.to_f] } }
    )
    expect(results.count).to eq 0

    dynamo_db.update_item(
      table_name: 'test',
      key: { 'creator_id' => 10,
             'date' => now.to_f },
      attribute_updates: {
        'data1' => {
          value: 'data2',
          action: 'ADD'
        },
        'foo' => {
          value: 'bar',
          action: 'ADD'
        }
      }
    )

    result1 = dynamo_db.get_item(table_name: 'test',
                                 key: { 'creator_id' => 10,
                                        'date' => now.to_f })

    expect(result1.item['foo']).to eq 'bar'
    expect(result1.item['data1']).to eq 'data2'

    dynamo_db.update_item(
      table_name: 'test',
      key: { 'creator_id' => 10,
             'date' => now.to_f },
      attribute_updates: {
        'foo' => {
          value: 'bar',
          action: 'DELETE'
        }
      }
    )

    result1 = dynamo_db.get_item(table_name: 'test',
                                 key: { 'creator_id' => 10,
                                        'date' => now.to_f })

    expect(result1.item['foo']).to be nil

    dynamo_db.delete_item(table_name: 'test',
                          key: { 'creator_id' => 10,
                                 'date' => now.to_f })

    result1 = dynamo_db.get_item(table_name: 'test',
                                 key: { 'creator_id' => 10,
                                        'date' => now.to_f })
    expect(result1.item).to be nil

    # Now delete table
    dynamo_db.delete_table(table_name: 'test')
    expect(dynamo_db.list_tables.table_names.length).to eq 0
  end

  it 'v1: test vistors' do
    dynamo_db = AWS::DynamoDB.new

    visitors_table = dynamo_db.tables.create('visitors', 10, 5,
                                             hash_key: { creator_id: :number },
                                             range_key: { date: :number })

    visitors_table.hash_key = [:creator_id, :number]
    visitors_table.range_key = [:date, :number]

    (0..10).each do |idx|
      visitors_table.items.put(creator_id: 1, date: Time.now.to_f - (60 * idx), target_id: 10 + idx)
    end

    ct = 0
    results = visitors_table.items.query(hash_value: 1, scan_index_forward: false)
    results.to_a.each do |item|
      expect(item.attributes['target_id'].to_i).to eq 10 + ct
      ct += 1
    end

    ct = 0
    results = visitors_table.items.query(hash_value: 1)
    results.to_a.each do |item|
      expect(item.attributes['target_id'].to_i).to eq 20 - ct
      ct += 1
    end

    visitors2_table = dynamo_db.tables.create('visitors2', 10, 5,
                                              hash_key: { profile_id: :number },
                                              range_key: { date_profile: :string })
    visitors2_table.hash_key = [:profile_id, :number]
    visitors2_table.range_key = [:date_profile, :string]

    profile_id = 1000
    (0..10).each do |idx|
      timestamp = Time.now.to_f - (60 * idx)
      visitors2_table.items.put(profile_id: idx, date_profile: "#{timestamp}:#{profile_id}", target_id: profile_id)
    end
    results = visitors2_table.items.query(hash_value: 1)
    expect(results.to_a.length).to eq 1
  end

  it 'v2: test vistors' do
    dynamo_db = Aws::DynamoDB::Client.new

    dynamo_db.create_table(
      table_name: 'visitors',
      provisioned_throughput: {
        read_capacity_units: 10,
        write_capacity_units: 10
      },
      attribute_definitions: [{ attribute_name: :creator_id,
                                attribute_type: 'N' },
                              { attribute_name: :date,
                                attribute_type: 'N' }],
      key_schema: [{ attribute_name: :creator_id, key_type: 'HASH' },
                   { attribute_name: :date, key_type: 'RANGE' }]
    )

    # Make some visitors
    10.times do |idx|
      dynamo_db.put_item(
        table_name: 'visitors',
        item: {
          'creator_id' => 1,
          'date' => Time.now.to_f,
          'target_id' => 10 + idx
        }
      )
    end

    # Query both directions
    results = dynamo_db.query(
      table_name: 'visitors',
      scan_index_forward: true,
      key_conditions: { 'creator_id' => { comparison_operator: 'EQ',
                                          attribute_value_list: [1] } }
    )

    ct = 0
    results.items.each do |item|
      expect(item['target_id'].to_i).to eq 10 + ct
      ct += 1
    end

    results = dynamo_db.query(
      table_name: 'visitors',
      scan_index_forward: false,
      key_conditions: { 'creator_id' => { comparison_operator: 'EQ',
                                          attribute_value_list: [1] } }
    )

    ct = 0
    results.items.each do |item|
      expect(item['target_id'].to_i).to eq 19 - ct
      ct += 1
    end

    # Nothing there
    results = dynamo_db.query(
      table_name: 'visitors',
      scan_index_forward: false,
      key_conditions: { 'creator_id' => { comparison_operator: 'EQ',
                                          attribute_value_list: [200] } }
    )
    expect(results.count).to eq 0

    # Make another table
    dynamo_db.create_table(
      table_name: 'visitors2',
      provisioned_throughput: {
        read_capacity_units: 10,
        write_capacity_units: 10
      },
      attribute_definitions: [{ attribute_name: :profile_id,
                                attribute_type: 'N' },
                              { attribute_name: :date_profile,
                                attribute_type: 'S' }],
      key_schema: [{ attribute_name: :profile_id, key_type: 'HASH' },
                   { attribute_name: :date_profile, key_type: 'RANGE' }]
    )

    profile_id = 1000

    10.times do |idx|
      timestamp = Time.now.to_f - (60 * idx)
      dynamo_db.put_item(
        table_name: 'visitors2',
        item: {
          'profile_id' => idx,
          'date_profile' => "#{timestamp}:#{profile_id}",
          'target_id' => profile_id
        }
      )
    end

    # Pull just one item out
    results = dynamo_db.query(
      table_name: 'visitors2',
      scan_index_forward: false,
      key_conditions: { 'profile_id' => { comparison_operator: 'EQ',
                                          attribute_value_list: [1] } }
    )
    expect(results.count).to eq 1

    # Test between
    dynamo_db.put_item(
      table_name: 'visitors',
      item: {
        'creator_id' => 2,
        'date' => Time.now.to_f
      }
    )

    dynamo_db.put_item(
      table_name: 'visitors',
      item: {
        'creator_id' => 2,
        'date' => (Time.now + 1).to_f
      }
    )

    results = dynamo_db.query(
      table_name: 'visitors',
      scan_index_forward: false,
      key_conditions: {
        'creator_id' => {
          comparison_operator: 'EQ',
          attribute_value_list: [2]
        },
        'date' => {
          comparison_operator: 'BETWEEN',
          attribute_value_list: \
            [(Time.now - 5).to_f,
             (Time.now + 5).to_f]
        }
      }
    )
    expect(results.count).to eq 2
  end

  it 'v1: should handle create, delete' do
    dynamo_db = AWS::DynamoDB::Client.new(api_version: '2012-08-10')

    test_table = dynamo_db.create_table(
      table_name: 'cd_table',
      provisioned_throughput: { read_capacity_units: 1, write_capacity_units: 1 },
      attribute_definitions: [
        { attribute_name: 'profile_id', attribute_type: 'N' },
        { attribute_name: 'visitor_id', attribute_type: 'N' }
      ],
      key_schema: [
        { attribute_name: 'profile_id', key_type: 'HASH' },
        { attribute_name: 'visitor_id', key_type: 'RANGE' }
      ],
      local_secondary_indexes: [{
        index_name: 'cd_ls_index',
        key_schema: [
          { attribute_name: 'profile_id', key_type: 'HASH' },
          { attribute_name: 'timestamp', key_type: 'RANGE' }
        ],
        projection: { projection_type: 'ALL' }
      }],
      global_secondary_indexes: [{
        index_name: 'cd_gs_index',
        key_schema: [
          { attribute_name: 'visitor_id', key_type: 'HASH' },
          { attribute_name: 'timestamp', key_type: 'RANGE' }
        ],
        projection: { projection_type: 'ALL' },
        provisioned_throughput: { read_capacity_units: 1, write_capacity_units: 1 }
      }]
    )
    dynamo_db.put_item(table_name: 'cd_table', item: { 'profile_id' => { 'n' => '1' }, 'visitor_id' => { 'n' => '2' },
                                                       'timestamp' => { 'n' => 3.to_s } })

    response = dynamo_db.get_item(table_name: 'cd_table', key: { 'profile_id' => { 'n' => '1' }, 'visitor_id' => { 'n' => '2' } })
    expect(response[:item]).not_to be_nil

    # Test query
    results = dynamo_db.query(table_name: 'cd_table', index_name: 'cd_gs_index', select: 'ALL_PROJECTED_ATTRIBUTES', key_conditions: {
                                'profile_id' => {
                                  comparison_operator: 'EQ',
                                  attribute_value_list: [
                                    { 'n' => '2' }
                                  ]
                                },
                                'timestamp' => {
                                  comparison_operator: 'LE',
                                  attribute_value_list: [
                                    { 'n' => 3.to_s }
                                  ]
                                }
                              })
    expect(results[:member].length).to eq 1

    dynamo_db.delete_item(table_name: 'cd_table', key: { 'profile_id' => { 'n' => '1' }, 'visitor_id' => { 'n' => '2' } })

    response = dynamo_db.get_item(table_name: 'cd_table', key: { 'profile_id' => { 'n' => '1' }, 'visitor_id' => { 'n' => '2' } })
    expect(response[:item]).to be_nil

    # Test query
    results = dynamo_db.query(table_name: 'cd_table', index_name: 'cd_gs_index', select: 'ALL_PROJECTED_ATTRIBUTES', key_conditions: {
                                'profile_id' => {
                                  comparison_operator: 'EQ',
                                  attribute_value_list: [
                                    { 'n' => '2' }
                                  ]
                                },
                                'timestamp' => {
                                  comparison_operator: 'LE',
                                  attribute_value_list: [
                                    { 'n' => 3.to_s }
                                  ]
                                }
                              })
    expect(results[:member].length.zero?).to be true
  end

  it 'v2: should handle create, delete' do
    dynamo_db = Aws::DynamoDB::Client.new

    dynamo_db.create_table(
      table_name: 'cd_table',
      provisioned_throughput: { read_capacity_units: 1,
                                write_capacity_units: 1 },
      attribute_definitions: [
        { attribute_name: 'profile_id', attribute_type: 'N' },
        { attribute_name: 'visitor_id', attribute_type: 'N' }
      ],
      key_schema: [
        { attribute_name: 'profile_id', key_type: 'HASH' },
        { attribute_name: 'visitor_id', key_type: 'RANGE' }
      ],
      local_secondary_indexes: [{
        index_name: 'cd_ls_index',
        key_schema: [
          { attribute_name: 'profile_id', key_type: 'HASH' },
          { attribute_name: 'timestamp', key_type: 'RANGE' }
        ],
        projection: { projection_type: 'ALL' }
      }],
      global_secondary_indexes: [{
        index_name: 'cd_gs_index',
        key_schema: [
          { attribute_name: 'visitor_id', key_type: 'HASH' },
          { attribute_name: 'timestamp', key_type: 'RANGE' }
        ],
        projection: { projection_type: 'ALL' },
        provisioned_throughput: { read_capacity_units: 1,
                                  write_capacity_units: 1 }
      }]
    )

    dynamo_db.put_item(table_name: 'cd_table',
                       item: { 'profile_id' => 1,
                               'visitor_id' => 2,
                               'timestamp' => 3 })

    response = dynamo_db.get_item(
      table_name: 'cd_table',
      key: { 'profile_id' => 1,
             'visitor_id' => 2 }
    )
    expect(response[:item]).not_to be_nil

    # Test query
    results = dynamo_db.query(
      table_name: 'cd_table',
      index_name: 'cd_gs_index',
      select: 'ALL_PROJECTED_ATTRIBUTES',
      key_conditions: {
        'profile_id' => {
          comparison_operator: 'EQ',
          attribute_value_list: [2]
        },
        'timestamp' => {
          comparison_operator: 'LE',
          attribute_value_list: [3]
        }
      }
    )
    expect(results.count).to eq 1

    dynamo_db.delete_item(
      table_name: 'cd_table',
      key: { 'profile_id' => 1, 'visitor_id' => 2 }
    )

    response = dynamo_db.get_item(
      table_name: 'cd_table',
      key: { 'profile_id' => 1, 'visitor_id' => 2 }
    )
    expect(response[:item]).to be_nil

    # Test query
    results = dynamo_db.query(
      table_name: 'cd_table',
      index_name: 'cd_gs_index',
      select: 'ALL_PROJECTED_ATTRIBUTES',
      key_conditions: {
        'profile_id' => {
          comparison_operator: 'EQ',
          attribute_value_list: [2]
        },
        'timestamp' => {
          comparison_operator: 'LE',
          attribute_value_list: [3]
        }
      }
    )

    expect(results.count).to eq 0
  end

  it 'v1: should handle local secondary indexes' do
    dynamo_db = AWS::DynamoDB::Client.new(api_version: '2012-08-10')

    test_table = dynamo_db.create_table(
      table_name: 'visited_by',
      provisioned_throughput: { read_capacity_units: 1, write_capacity_units: 1 },
      attribute_definitions: [
        { attribute_name: 'profile_id', attribute_type: 'N' },
        { attribute_name: 'visitor_id', attribute_type: 'N' }
      ],
      key_schema: [
        { attribute_name: 'profile_id', key_type: 'HASH' },
        { attribute_name: 'visitor_id', key_type: 'RANGE' }
      ],
      local_secondary_indexes: [{
        index_name: 'ls_index',
        key_schema: [
          { attribute_name: 'profile_id', key_type: 'HASH' },
          { attribute_name: 'timestamp', key_type: 'RANGE' }
        ],
        projection: { projection_type: 'ALL' }
      }],
      global_secondary_indexes: [{
        index_name: 'gs_index',
        key_schema: [
          { attribute_name: 'visitor_id', key_type: 'HASH' },
          { attribute_name: 'timestamp', key_type: 'RANGE' }
        ],
        projection: { projection_type: 'ALL' },
        provisioned_throughput: { read_capacity_units: 1, write_capacity_units: 1 }
      }]
    )

    now = Time.now.to_i

    # Test put and get

    # 2 visits 1
    dynamo_db.put_item(table_name: 'visited_by', item: { 'profile_id' => { 'n' => '1' }, 'visitor_id' => { 'n' => '2' },
                                                         'timestamp' => { 'n' => 3.to_s } })
    item = dynamo_db.get_item(table_name: 'visited_by', key: { 'profile_id' => { 'n' => '1' }, 'visitor_id' => { 'n' => '2' } })
    expect(item).not_to be_nil
    expect(item[:item]['profile_id'][:n]).to eq '1'
    expect(item[:item]['timestamp'][:n]).to eq '3'

    # 2 visits 1 again
    dynamo_db.put_item(table_name: 'visited_by', item: { 'profile_id' => { 'n' => '1' }, 'visitor_id' => { 'n' => '2' },
                                                         'timestamp' => { 'n' => 4.to_s } })
    item = dynamo_db.get_item(table_name: 'visited_by', key: { 'profile_id' => { 'n' => '1' }, 'visitor_id' => { 'n' => '2' } })
    expect(item).not_to be_nil
    expect(item[:item]['profile_id'][:n]).to eq '1'
    expect(item[:item]['timestamp'][:n]).to eq '4'

    # 2 visits 1 a third time, with timestamp of now
    dynamo_db.put_item(table_name: 'visited_by', item: { 'profile_id' => { 'n' => '1' }, 'visitor_id' => { 'n' => '2' },
                                                         'timestamp' => { 'n' => now.to_s } })

    item = dynamo_db.get_item(table_name: 'visited_by', key: { 'profile_id' => { 'n' => '1' }, 'visitor_id' => { 'n' => '2' } })
    expect(item).not_to be_nil
    expect(item[:item]['profile_id'][:n]).to eq '1'

    item = dynamo_db.get_item(table_name: 'visited_by', key: { 'profile_id' => { 'n' => '2' }, 'visitor_id' => { 'n' => '2' } })
    expect(item[:item]).to be_nil

    # Try the global secondary index
    results = dynamo_db.query(table_name: 'visited_by', index_name: 'gs_index', select: 'ALL_PROJECTED_ATTRIBUTES', key_conditions: {
                                'profile_id' => {
                                  comparison_operator: 'EQ',
                                  attribute_value_list: [
                                    { 'n' => '2' }
                                  ]
                                },
                                'timestamp' => {
                                  comparison_operator: 'LE',
                                  attribute_value_list: [
                                    { 'n' => Time.now.to_i.to_s }
                                  ]
                                }
                              })
    expect(results[:member].length).to eq 1

    # Try the local secondary index
    results = dynamo_db.query(table_name: 'visited_by', index_name: 'ls_index', select: 'ALL_PROJECTED_ATTRIBUTES', key_conditions: {
                                'profile_id' => {
                                  comparison_operator: 'EQ',
                                  attribute_value_list: [
                                    { 'n' => '1' }
                                  ]
                                },
                                'timestamp' => {
                                  comparison_operator: 'LE',
                                  attribute_value_list: [
                                    { 'n' => Time.now.to_i.to_s }
                                  ]
                                }
                              })
    expect(results[:member].length).to eq 1

    results = dynamo_db.query(table_name: 'visited_by', index_name: 'ls_index', select: 'ALL_PROJECTED_ATTRIBUTES', key_conditions: {
                                'profile_id' => {
                                  comparison_operator: 'EQ',
                                  attribute_value_list: [
                                    { 'n' => '1' }
                                  ]
                                },
                                'timestamp' => {
                                  comparison_operator: 'LE',
                                  attribute_value_list: [
                                    { 'n' => (Time.now.utc.to_i - 2).to_s }
                                  ]
                                }
                              })
    expect(results[:member].length).to eq 0

    dynamo_db.put_item(table_name: 'visited_by', item: { 'profile_id' => { 'n' => '1' }, 'visitor_id' => { 'n' => '3' }, 'timestamp' => { 'n' => Time.now.utc.to_i.to_s } })
    dynamo_db.put_item(table_name: 'visited_by', item: { 'profile_id' => { 'n' => '1' }, 'visitor_id' => { 'n' => '4' }, 'timestamp' => { 'n' => Time.now.utc.to_i.to_s } })

    results = dynamo_db.query(table_name: 'visited_by', index_name: 'ls_index', select: 'ALL_PROJECTED_ATTRIBUTES', key_conditions: {
                                'profile_id' => {
                                  comparison_operator: 'EQ',
                                  attribute_value_list: [
                                    { 'n' => '1' }
                                  ]
                                },
                                'timestamp' => {
                                  comparison_operator: 'LE',
                                  attribute_value_list: [
                                    { 'n' => Time.now.to_i.to_s }
                                  ]
                                }
                              })
    expect(results[:member].length).to eq 3

    # Add some more profiles visited by 2
    (3...10).each do |idx|
      dynamo_db.put_item(table_name: 'visited_by', item: { 'profile_id' => { 'n' => idx.to_s }, 'visitor_id' => { 'n' => '2' },
                                                           'timestamp' => { 'n' => (now - idx).to_s } })
    end

    results = dynamo_db.query(table_name: 'visited_by', index_name: 'gs_index', select: 'ALL_PROJECTED_ATTRIBUTES', key_conditions: {
                                'profile_id' => {
                                  comparison_operator: 'EQ',
                                  attribute_value_list: [
                                    { 'n' => '2' }
                                  ]
                                },
                                'timestamp' => {
                                  comparison_operator: 'LE',
                                  attribute_value_list: [
                                    { 'n' => Time.now.to_i.to_s }
                                  ]
                                }
                              })
    expect(results[:member].length).to eq 8
    expect(results[:member].first['profile_id'][:n]).to eq '9'
    expect(results[:member].last['profile_id'][:n]).to eq '1'

    # reverse
    results = dynamo_db.query(table_name: 'visited_by',
                              scan_index_forward: false,
                              index_name: 'gs_index', select: 'ALL_PROJECTED_ATTRIBUTES', key_conditions: {
                                'profile_id' => {
                                  comparison_operator: 'EQ',
                                  attribute_value_list: [
                                    { 'n' => '2' }
                                  ]
                                },
                                'timestamp' => {
                                  comparison_operator: 'LE',
                                  attribute_value_list: [
                                    { 'n' => Time.now.to_i.to_s }
                                  ]
                                }
                              })
    expect(results[:member].length).to eq 8
    expect(results[:member].first['profile_id'][:n]).to eq '1'
    expect(results[:member].last['profile_id'][:n]).to eq '9'
  end

  it 'v2: should handle local secondary indexes' do
    dynamo_db = Aws::DynamoDB::Client.new

    dynamo_db.create_table(
      table_name: 'visited_by',
      provisioned_throughput: { read_capacity_units: 1,
                                write_capacity_units: 1 },
      attribute_definitions: [
        { attribute_name: 'profile_id', attribute_type: 'N' },
        { attribute_name: 'visitor_id', attribute_type: 'N' }
      ],
      key_schema: [
        { attribute_name: 'profile_id', key_type: 'HASH' },
        { attribute_name: 'visitor_id', key_type: 'RANGE' }
      ],
      local_secondary_indexes: [{
        index_name: 'ls_index',
        key_schema: [
          { attribute_name: 'profile_id', key_type: 'HASH' },
          { attribute_name: 'timestamp', key_type: 'RANGE' }
        ],
        projection: { projection_type: 'ALL' }
      }],
      global_secondary_indexes: [{
        index_name: 'gs_index',
        key_schema: [
          { attribute_name: 'visitor_id', key_type: 'HASH' },
          { attribute_name: 'timestamp', key_type: 'RANGE' }
        ],
        projection: { projection_type: 'ALL' },
        provisioned_throughput: { read_capacity_units: 1,
                                  write_capacity_units: 1 }
      }]
    )

    now = Time.now.to_i

    # Test put and get

    # 2 visits 1
    dynamo_db.put_item(
      table_name: 'visited_by',
      item: { 'profile_id' => 1,
              'visitor_id' => 2,
              'timestamp' => 3 }
    )
    item = dynamo_db.get_item(
      table_name: 'visited_by',
      key: { 'profile_id' => 1,
             'visitor_id' => 2 }
    )
    expect(item.item).not_to be nil
    expect(item.item['profile_id']).to eq 1
    expect(item.item['timestamp']).to eq 3

    # 2 visits 1 again
    dynamo_db.put_item(
      table_name: 'visited_by',
      item: { 'profile_id' => 1,
              'visitor_id' => 2,
              'timestamp' => 4 }
    )

    item = dynamo_db.get_item(
      table_name: 'visited_by',
      key: { 'profile_id' => 1,
             'visitor_id' => 2 }
    )
    expect(item.item).not_to be nil
    expect(item.item['profile_id']).to eq 1
    expect(item.item['timestamp']).to eq 4

    # 2 visits 1 a third time, with timestamp of now
    dynamo_db.put_item(
      table_name: 'visited_by',
      item: { 'profile_id' => 1,
              'visitor_id' => 2,
              'timestamp' => now }
    )
    item = dynamo_db.get_item(
      table_name: 'visited_by',
      key: { 'profile_id' => 1,
             'visitor_id' => 2 }
    )
    expect(item.item).not_to be nil
    expect(item.item['profile_id']).to eq 1

    item = dynamo_db.get_item(
      table_name: 'visited_by',
      key: { 'profile_id' => 2,
             'visitor_id' => 2 }
    )
    expect(item.item).to be nil

    # Try the global secondary index
    results = dynamo_db.query(
      table_name: 'visited_by',
      index_name: 'gs_index',
      select: 'ALL_PROJECTED_ATTRIBUTES',
      key_conditions: {
        'profile_id' => {
          comparison_operator: 'EQ',
          attribute_value_list: [2]
        },
        'timestamp' => {
          comparison_operator: 'LE',
          attribute_value_list: [Time.now.to_i]
        }
      }
    )
    expect(results.count).to eq 1

    # Try the local secondary index
    results = dynamo_db.query(
      table_name: 'visited_by',
      index_name: 'ls_index',
      select: 'ALL_PROJECTED_ATTRIBUTES',
      key_conditions: {
        'profile_id' => {
          comparison_operator: 'EQ',
          attribute_value_list: [1]
        },
        'timestamp' => {
          comparison_operator: 'LE',
          attribute_value_list: [Time.now.to_i]
        }
      }
    )
    expect(results.count).to eq 1

    results = dynamo_db.query(
      table_name: 'visited_by',
      index_name: 'ls_index',
      select: 'ALL_PROJECTED_ATTRIBUTES',
      key_conditions: {
        'profile_id' => {
          comparison_operator: 'EQ',
          attribute_value_list: [1]
        },
        'timestamp' => {
          comparison_operator: 'LE',
          attribute_value_list: [Time.now.to_i - 2]
        }
      }
    )
    expect(results.count).to eq 0

    # 3 and 4 visit
    (3..4).each do |visitor_id|
      dynamo_db.put_item(
        table_name: 'visited_by',
        item: { 'profile_id' => 1,
                'visitor_id' => visitor_id,
                'timestamp' => Time.now.to_i }
      )
    end

    results = dynamo_db.query(
      table_name: 'visited_by',
      index_name: 'ls_index',
      select: 'ALL_PROJECTED_ATTRIBUTES',
      key_conditions: {
        'profile_id' => {
          comparison_operator: 'EQ',
          attribute_value_list: [1]
        },
        'timestamp' => {
          comparison_operator: 'LE',
          attribute_value_list: [Time.now.to_i]
        }
      }
    )

    expect(results.count).to eq 3

    # Add some more profiles visited by 2
    (3...10).each do |idx|
      dynamo_db.put_item(
        table_name: 'visited_by',
        item: { 'profile_id' => idx,
                'visitor_id' => 2,
                'timestamp' => (now - idx).to_i }
      )
    end

    results = dynamo_db.query(
      table_name: 'visited_by',
      index_name: 'gs_index',
      select: 'ALL_PROJECTED_ATTRIBUTES',
      key_conditions: {
        'profile_id' => {
          comparison_operator: 'EQ',
          attribute_value_list: [2]
        },
        'timestamp' => {
          comparison_operator: 'LE',
          attribute_value_list: [Time.now.to_i]
        }
      }
    )
    expect(results.count).to eq 8
    expect(results.items.first['profile_id']).to eq 9
    expect(results.items.last['profile_id']).to eq 1

    # reverse
    results = dynamo_db.query(
      table_name: 'visited_by',
      index_name: 'gs_index',
      scan_index_forward: false,
      select: 'ALL_PROJECTED_ATTRIBUTES',
      key_conditions: {
        'profile_id' => {
          comparison_operator: 'EQ',
          attribute_value_list: [2]
        },
        'timestamp' => {
          comparison_operator: 'LE',
          attribute_value_list: [Time.now.to_i]
        }
      }
    )
    expect(results.count).to eq 8
    expect(results.items.first['profile_id']).to eq 1
    expect(results.items.last['profile_id']).to eq 9
  end

  it 'v1: should handle update item' do
    dynamo_db = AWS::DynamoDB::Client.new(api_version: '2012-08-10')

    test_table = dynamo_db.create_table(
      table_name: 'visitor_counts',
      provisioned_throughput: { read_capacity_units: 1, write_capacity_units: 1 },
      attribute_definitions: [
        { attribute_name: 'profile_id', attribute_type: 'N' },
        { attribute_name: 'count', attribute_type: 'N' }
      ],
      key_schema: [
        { attribute_name: 'profile_id', key_type: 'HASH' },
        { attribute_name: 'count', key_type: 'RANGE' }
      ],
      local_secondary_indexes: [{
        index_name: 'ls_index',
        key_schema: [
          { attribute_name: 'profile_id', key_type: 'HASH' },
          { attribute_name: 'count', key_type: 'RANGE' }
        ],
        projection: { projection_type: 'ALL' }
      }]
    )

    dynamo_db.update_item(table_name: 'visitor_counts',
                          key: { 'profile_id' => { 'n' => 1.to_s } },
                          attribute_updates: {
                            'count' => { action: 'ADD', value: { 'n' => 1.to_s } }
                          })
  end

  it 'v2: should handle update item' do
    dynamo_db = Aws::DynamoDB::Client.new

    dynamo_db.create_table(
      table_name: 'visitor_counts',
      provisioned_throughput: { read_capacity_units: 1,
                                write_capacity_units: 1 },
      attribute_definitions: [
        { attribute_name: 'profile_id', attribute_type: 'N' },
        { attribute_name: 'count', attribute_type: 'N' }
      ],
      key_schema: [
        { attribute_name: 'profile_id', key_type: 'HASH' },
        { attribute_name: 'count', key_type: 'RANGE' }
      ],
      local_secondary_indexes: [{
        index_name: 'ls_index',
        key_schema: [
          { attribute_name: 'profile_id', key_type: 'HASH' },
          { attribute_name: 'count', key_type: 'RANGE' }
        ],
        projection: { projection_type: 'ALL' }
      }]
    )

    dynamo_db.update_item(
      table_name: 'visitor_counts',
      key: { 'profile_id' => 1 },
      attribute_updates: {
        'count' => { action: 'ADD', value: 1 }
      }
    )
    dynamo_db.update_item(
      table_name: 'visitor_counts',
      key: { 'profile_id' => 1 },
      attribute_updates: {
        'count' => { action: 'ADD', value: 1 }
      }
    )

    result1 = dynamo_db.get_item(table_name: 'visitor_counts',
                                 key: { 'profile_id' => 1 })
    expect(result1.item['count']).to eq 2
  end

  it 'v1: should handle get item when no values' do
    dynamo_db = AWS::DynamoDB::Client.new(api_version: '2012-08-10')

    dynamo_db.create_table(
      table_name: 'secrets',
      provisioned_throughput: \
        { read_capacity_units: 1, write_capacity_units: 1 },
      attribute_definitions: [
        { attribute_name: 'name', attribute_type: 'S' }
      ],
      key_schema: [
        { attribute_name: 'name', key_type: 'HASH' }
      ]
    )
    value = dynamo_db.get_item(
      table_name: 'secrets',
      key: { 'name' => { 's' => 'hi'.to_s } }
    )

    expect(value[:item]).to be nil
  end

  it 'v2: should handle get item when no values' do
    dynamo_db = Aws::DynamoDB::Client.new

    dynamo_db.create_table(
      table_name: 'secrets',
      provisioned_throughput: \
        { read_capacity_units: 1, write_capacity_units: 1 },
      attribute_definitions: [
        { attribute_name: 'name', attribute_type: 'S' }
      ],
      key_schema: [
        { attribute_name: 'name', key_type: 'HASH' }
      ]
    )
    value = dynamo_db.get_item(
      table_name: 'secrets',
      key: { 'name' => 'hi' }
    )

    expect(value[:item]).to be nil
  end
end
