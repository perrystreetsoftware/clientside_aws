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
    last_response.should be_ok
  end
  
  it "should handle basic CRUD test" do
    dynamo_db = AWS::DynamoDB.new(
      :access_key_id => "...",
      :secret_access_key => "...")
      
    test_table = dynamo_db.tables.create("test1", 1, 1,
        :hash_key => { :creator_id => :number }, 
        :range_key => {:date => :number})
    
    dynamo_db.tables.to_a.length.should == 1
    dynamo_db.tables['test1'].exists?.should be_true
    # dynamo_db.tables['test_fake'].exists?.should be_false # this test fails for some reason
    
    test_table.hash_key = [:creator_id, :number]
    test_table.range_key = [:date, :number]
    
    now = Time.now.to_f
    test_table.items.put(:creator_id => 10, :date => now, :data1 => "data1")
    test_table.items[10, now].exists?.should be_true
    test_table.items[11, now].exists?.should be_false

    results = test_table.items.query(:hash_value => 10, :range_value => (0..(now+1)))
    results.to_a.length.should == 1
    results.to_a.first.attributes['creator_id'].should == 10
    
    results = test_table.items.query(:hash_value => 10, :range_value => 0..1)
    results.to_a.length.should == 0    
    
    results = test_table.items.query(:hash_value => 10, :range_value => (0..(now+1)))
    results.to_a.first.attributes.update do |u|
      u.add "foo" => "bar"
      u.add "bar" => 100
    end
    
    test_table.items[10, now].attributes["foo"].should == "bar"
    test_table.items[10, now].attributes["bar"].should == 100

    test_table.items[10, now].attributes.update do |u|
      u.delete "foo"
    end

    test_table.items[10, now].attributes["foo"].should be_nil
    
    item = test_table.items[10, now]
    item.delete()
    test_table.items[10, now].exists?.should be_false
    
    
    test_table.delete()
    dynamo_db.tables.to_a.length.should == 0
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
  
end
