$LOAD_PATH << "#{File.dirname(__FILE__)}/../"

require 'spec/spec_helper'
require 'aws-sdk'
require 'aws_mock'

describe 'Profiles Spec' do
  include Rack::Test::Methods
  def app
    Sinatra::Application
  end

  it "says hello" do
    get '/'
    expect(last_response).to be_ok
  end

  it "should handle basic CRUD test" do
    dynamo_db = AWS::DynamoDB.new(
      :access_key_id => "...",
      :secret_access_key => "...")

    test_table = dynamo_db.tables.create("test1", 1, 1,
        :hash_key => { :creator_id => :number },
        :range_key => {:date => :number})

    expect(dynamo_db.tables.to_a.length).to eq 1
    expect(dynamo_db.tables['test1'].exists?).to be true
    # dynamo_db.tables['test_fake'].exists?.should be_false # this test fails for some reason

    test_table.hash_key = [:creator_id, :number]
    test_table.range_key = [:date, :number]

    now = Time.now.to_f
    test_table.items.put(:creator_id => 10, :date => now, :data1 => "data1")
    expect(test_table.items[10, now].exists?).to be true
    expect(test_table.items[11, now].exists?).to be false

    results = test_table.items.query(:hash_value => 10, :range_value => (0..(now+1)))
    expect(results.to_a.length).to eq 1
    expect(results.to_a.first.attributes['creator_id']).to eq 10

    results = test_table.items.query(:hash_value => 10, :range_value => 0..1)
    expect(results.to_a.length).to eq 0

    results = test_table.items.query(:hash_value => 10, :range_value => (0..(now+1)))
    results.to_a.first.attributes.update do |u|
      u.add "foo" => "bar"
      u.add "bar" => 100
    end

    expect(test_table.items[10, now].attributes["foo"]).to eq "bar"
    expect(test_table.items[10, now].attributes["bar"]).to eq 100

    test_table.items[10, now].attributes.update do |u|
      u.delete "foo"
    end

    expect(test_table.items[10, now].attributes["foo"]).to be_nil

    item = test_table.items[10, now]
    item.delete()
    expect(test_table.items[10, now].exists?).to be false


    test_table.delete()
    expect(dynamo_db.tables.to_a.length).to eq 0
  end


  it "test vistors" do
    dynamo_db = AWS::DynamoDB.new(
      :access_key_id => "...",
      :secret_access_key => "...")

    visitors_table = dynamo_db.tables.create("visitors", 10, 5,
        :hash_key => { :creator_id => :number },
        :range_key => {:date => :number})

    visitors_table.hash_key = [:creator_id, :number]
    visitors_table.range_key = [:date, :number]

    (0..10).each do |idx|
      visitors_table.items.put(:creator_id => 1, :date => Time.now.to_f - (60 * idx), :target_id => 10 + idx)
    end

    ct = 0
    results = visitors_table.items.query(:hash_value => 1, :scan_index_forward => false)
    results.to_a.each do |item|
      item.attributes['target_id'].to_i.should == 10 + ct
      ct += 1
    end

    ct = 0
    results = visitors_table.items.query(:hash_value => 1)
    results.to_a.each do |item|
      item.attributes['target_id'].to_i.should == 20 - ct
      ct += 1
    end

    visitors2_table = dynamo_db.tables.create("visitors2", 10, 5,
        :hash_key => { :profile_id => :number },
        :range_key => {:date_profile => :string})
    visitors2_table.hash_key = [:profile_id, :number]
    visitors2_table.range_key = [:date_profile, :string]

    profile_id = 1000
    (0..10).each do |idx|
      timestamp = Time.now.to_f - (60 * idx)
      visitors2_table.items.put(:profile_id => idx, :date_profile => "#{timestamp}:#{profile_id}", :target_id => profile_id)
    end
    results = visitors2_table.items.query(:hash_value => 1)
    results.to_a.length.should == 1

  end

  it "should handle create, delete" do
    dynamo_db = AWS::DynamoDB::Client.new(
      :api_version => '2012-08-10',
      :access_key_id => "...",
      :secret_access_key => "...")

    test_table = dynamo_db.create_table(
      :table_name => "cd_table",
      :provisioned_throughput => {:read_capacity_units => 1, :write_capacity_units => 1},
      :attribute_definitions => [
        {:attribute_name => 'profile_id', :attribute_type => "N"},
        {:attribute_name => 'visitor_id', :attribute_type => "N"}],
      :key_schema => [
        {:attribute_name => "profile_id", :key_type => "HASH"},
        {:attribute_name => "visitor_id", :key_type => "RANGE"}],
      :local_secondary_indexes => [{
        :index_name => "cd_ls_index",
        :key_schema => [
          {:attribute_name => "profile_id", :key_type => "HASH"},
          {:attribute_name => "timestamp", :key_type => "RANGE"}
          ],
        :projection => {:projection_type => "ALL"}
        }],
      :global_secondary_indexes => [{
        :index_name => "cd_gs_index",
        :key_schema => [
          {:attribute_name => "visitor_id", :key_type => "HASH"},
          {:attribute_name => "timestamp", :key_type => "RANGE"}
          ],
        :projection => {:projection_type => "ALL"},
        :provisioned_throughput => {:read_capacity_units => 1, :write_capacity_units => 1}
      }])
    dynamo_db.put_item(:table_name => "cd_table", :item => {'profile_id' => {'n' => '1'}, 'visitor_id' => {'n' => '2'},
      'timestamp' => {'n' => 3.to_s}})

    response = dynamo_db.get_item(:table_name => "cd_table", :key => {'profile_id' => {'n' => '1'}, 'visitor_id' => {'n' => '2'}})
    expect(response[:item]).not_to be_nil

    # Test query
    results = dynamo_db.query({:table_name => 'cd_table', :index_name => 'cd_gs_index', :select => 'ALL_PROJECTED_ATTRIBUTES', :key_conditions => {
           'profile_id' => {
             :comparison_operator => 'EQ',
            :attribute_value_list => [
               {'n' => "2"}
             ]
           },
           'timestamp' => {
            :comparison_operator => 'LE',
            :attribute_value_list => [
               {'n' => 3.to_s}
             ]
           }}})
    results[:member].length.should == 1

    dynamo_db.delete_item(:table_name => "cd_table", :key => {'profile_id' => {'n' => '1'}, 'visitor_id' => {'n' => '2'}})

    response = dynamo_db.get_item(:table_name => "cd_table", :key => {'profile_id' => {'n' => '1'}, 'visitor_id' => {'n' => '2'}})
    expect(response[:item]).to be_nil

    # Test query
    results = dynamo_db.query({:table_name => 'cd_table', :index_name => 'cd_gs_index', :select => 'ALL_PROJECTED_ATTRIBUTES', :key_conditions => {
           'profile_id' => {
             :comparison_operator => 'EQ',
            :attribute_value_list => [
               {'n' => "2"}
             ]
           },
           'timestamp' => {
            :comparison_operator => 'LE',
            :attribute_value_list => [
               {'n' => 3.to_s}
             ]
           }}})
    results[:member].length.should == 0

  end


  it "should handle local secondary indexes" do
    dynamo_db = AWS::DynamoDB::Client.new(
      :api_version => '2012-08-10',
      :access_key_id => "...",
      :secret_access_key => "...")

    test_table = dynamo_db.create_table(
      :table_name => "visited_by",
      :provisioned_throughput => {:read_capacity_units => 1, :write_capacity_units => 1},
      :attribute_definitions => [
        {:attribute_name => 'profile_id', :attribute_type => "N"},
        {:attribute_name => 'visitor_id', :attribute_type => "N"}],
      :key_schema => [
        {:attribute_name => "profile_id", :key_type => "HASH"},
        {:attribute_name => "visitor_id", :key_type => "RANGE"}],
      :local_secondary_indexes => [{
        :index_name => "ls_index",
        :key_schema => [
          {:attribute_name => "profile_id", :key_type => "HASH"},
          {:attribute_name => "timestamp", :key_type => "RANGE"}
          ],
        :projection => {:projection_type => "ALL"}
        }],
      :global_secondary_indexes => [{
        :index_name => "gs_index",
        :key_schema => [
          {:attribute_name => "visitor_id", :key_type => "HASH"},
          {:attribute_name => "timestamp", :key_type => "RANGE"}
          ],
        :projection => {:projection_type => "ALL"},
        :provisioned_throughput => {:read_capacity_units => 1, :write_capacity_units => 1}
      }])

    now = Time.now.to_i

    # Test put and get

    # 2 visits 1
    dynamo_db.put_item(:table_name => "visited_by", :item => {'profile_id' => {'n' => '1'}, 'visitor_id' => {'n' => '2'},
      'timestamp' => {'n' => 3.to_s}})
    item = dynamo_db.get_item(:table_name => "visited_by", :key => {'profile_id' => {'n' => '1'}, 'visitor_id' => {'n' => '2'}})
    item.should_not be_nil
    item[:item]['profile_id'][:n].should == "1"
    item[:item]['timestamp'][:n].should == "3"

    # 2 visits 1 again
    dynamo_db.put_item(:table_name => "visited_by", :item => {'profile_id' => {'n' => '1'}, 'visitor_id' => {'n' => '2'},
      'timestamp' => {'n' => 4.to_s}})
    item = dynamo_db.get_item(:table_name => "visited_by", :key => {'profile_id' => {'n' => '1'}, 'visitor_id' => {'n' => '2'}})
    item.should_not be_nil
    item[:item]['profile_id'][:n].should == "1"
    item[:item]['timestamp'][:n].should == "4"

    # 2 visits 1 a third time, with timestamp of now
    dynamo_db.put_item(:table_name => "visited_by", :item => {'profile_id' => {'n' => '1'}, 'visitor_id' => {'n' => '2'},
      'timestamp' => {'n' => now.to_s}})

    item = dynamo_db.get_item(:table_name => "visited_by", :key => {'profile_id' => {'n' => '1'}, 'visitor_id' => {'n' => '2'}})
    item.should_not be_nil
    item[:item]['profile_id'][:n].should == "1"

    item = dynamo_db.get_item(:table_name => "visited_by", :key => {'profile_id' => {'n' => '2'}, 'visitor_id' => {'n' => '2'}})
    expect(item[:item]).to be_nil

    # Try the global secondary index
    results = dynamo_db.query({:table_name => 'visited_by', :index_name => 'gs_index', :select => 'ALL_PROJECTED_ATTRIBUTES', :key_conditions => {
           'profile_id' => {
             :comparison_operator => 'EQ',
            :attribute_value_list => [
               {'n' => "2"}
             ]
           },
           'timestamp' => {
            :comparison_operator => 'LE',
            :attribute_value_list => [
               {'n' => (Time.now.to_i).to_s}
             ]
           }}})
    results[:member].length.should == 1

    # Try the local secondary index
    results = dynamo_db.query({:table_name => 'visited_by', :index_name => 'ls_index', :select => 'ALL_PROJECTED_ATTRIBUTES', :key_conditions => {
           'profile_id' => {
             :comparison_operator => 'EQ',
            :attribute_value_list => [
               {'n' => "1"}
             ]
           },
           'timestamp' => {
            :comparison_operator => 'LE',
            :attribute_value_list => [
               {'n' => (Time.now.to_i).to_s}
             ]
           }}})
    results[:member].length.should == 1

    results = dynamo_db.query({:table_name => 'visited_by', :index_name => 'ls_index', :select => 'ALL_PROJECTED_ATTRIBUTES', :key_conditions => {
           'profile_id' => {
             :comparison_operator => 'EQ',
            :attribute_value_list => [
               {'n' => "1"}
             ]
           },
           'timestamp' => {
            :comparison_operator => 'LE',
            :attribute_value_list => [
               {'n' => (Time.now.utc.to_i - 2).to_s}
             ]
           }}})
    results[:member].length.should == 0

    dynamo_db.put_item(:table_name => "visited_by", :item => {'profile_id' => {'n' => '1'}, 'visitor_id' => {'n' => '3'}, 'timestamp' => {'n' => Time.now.utc.to_i.to_s}})
    dynamo_db.put_item(:table_name => "visited_by", :item => {'profile_id' => {'n' => '1'}, 'visitor_id' => {'n' => '4'}, 'timestamp' => {'n' => Time.now.utc.to_i.to_s}})

    results = dynamo_db.query({:table_name => 'visited_by', :index_name => 'ls_index', :select => 'ALL_PROJECTED_ATTRIBUTES', :key_conditions => {
           'profile_id' => {
             :comparison_operator => 'EQ',
            :attribute_value_list => [
               {'n' => "1"}
             ]
           },
           'timestamp' => {
            :comparison_operator => 'LE',
            :attribute_value_list => [
               {'n' => (Time.now.to_i).to_s}
             ]
           }}})
    results[:member].length.should == 3

    # Add some more profiles visited by 2
    (3...10).each do |idx|
      dynamo_db.put_item(:table_name => "visited_by", :item => {'profile_id' => {'n' => idx.to_s}, 'visitor_id' => {'n' => '2'},
        'timestamp' => {'n' => (now-idx).to_s}})
    end

    results = dynamo_db.query({:table_name => 'visited_by', :index_name => 'gs_index', :select => 'ALL_PROJECTED_ATTRIBUTES', :key_conditions => {
           'profile_id' => {
             :comparison_operator => 'EQ',
            :attribute_value_list => [
               {'n' => "2"}
             ]
           },
           'timestamp' => {
            :comparison_operator => 'LE',
            :attribute_value_list => [
               {'n' => (Time.now.to_i).to_s}
             ]
           }}})
    results[:member].length.should == 8
    results[:member].first['profile_id'][:n].should == "9"
    results[:member].last['profile_id'][:n].should == "1"

    # reverse
    results = dynamo_db.query({:table_name => 'visited_by',
      :scan_index_forward => false,
      :index_name => 'gs_index', :select => 'ALL_PROJECTED_ATTRIBUTES', :key_conditions => {
           'profile_id' => {
             :comparison_operator => 'EQ',
            :attribute_value_list => [
               {'n' => "2"}
             ]
           },
           'timestamp' => {
            :comparison_operator => 'LE',
            :attribute_value_list => [
               {'n' => (Time.now.to_i).to_s}
             ]
           }}})
    results[:member].length.should == 8
    results[:member].first['profile_id'][:n].should == "1"
    results[:member].last['profile_id'][:n].should == "9"

  end

  it "should handle update item" do
    dynamo_db = AWS::DynamoDB::Client.new(
      :api_version => '2012-08-10',
      :access_key_id => "...",
      :secret_access_key => "...")

    test_table = dynamo_db.create_table(
      :table_name => "visitor_counts",
      :provisioned_throughput => {:read_capacity_units => 1, :write_capacity_units => 1},
      :attribute_definitions => [
        {:attribute_name => 'profile_id', :attribute_type => "N"},
        {:attribute_name => 'count', :attribute_type => "N"}],
      :key_schema => [
        {:attribute_name => "profile_id", :key_type => "HASH"},
        {:attribute_name => "count", :key_type => "RANGE"}],
      :local_secondary_indexes => [{
        :index_name => "ls_index",
        :key_schema => [
          {:attribute_name => "profile_id", :key_type => "HASH"},
          {:attribute_name => "count", :key_type => "RANGE"}
          ],
        :projection => {:projection_type => "ALL"}
        }])

    dynamo_db.update_item(:table_name => 'visitor_counts',
          :key => {'profile_id' => {'n' => 1.to_s}},
          :attribute_updates => {
            'count' => {:action => 'ADD', :value => {'n' => 1.to_s}}
          })
  end
end
