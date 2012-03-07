require 'spec/spec_helper'
require 'aws-sdk'
require 'dynamodb_mock'

describe 'Profiles Spec' do
  include Rack::Test::Methods
  def app
    Sinatra::Application
  end

  it "says hello" do
    get '/'
    last_response.should be_ok
  end
  
  it "fake create with lib" do
    dynamo_db = AWS::DynamoDB.new(
      :access_key_id => "...",
      :secret_access_key => "...")
    
    table = dynamo_db.tables.create("my-table", 10, 5,
        :hash_key => { :id => :number }, 
        :range_key => {:date => :number})
    table.hash_key = [:id, :number]
    table.range_key = [:date, :number]
    
    item = table.items.create('id' => 12343, 'date' => 100, 'foo' => 'bar0', 'bizzy' => 'batty')
    item = table.items.create('id' => 12344, 'date' => 10, 'foo' => 'bar1', 'bizzy' => 'batty')
    item = table.items.create('id' => 12345, 'date' => 1, 'foo' => 'bar2', 'bizzy' => 'batty')
    item = table.items.create('id' => 12345, 'date' => 2, 'foo' => 'bar3', 'bizzy' => 'batty')
    item = table.items[12345, 1]    
    item.attributes['foo'].should == "bar2"
    item.attributes['bizzy'].should == "batty"
    
    results = table.items.query(
      :hash_value => 12345,
      :range_value => 1..10
    )

    results.to_a.length.should == 2
    results.to_a.first.attributes['id'].should == 12345
    results.to_a.first.attributes['date'].to_i.should == 1
    results.to_a.last.attributes['id'].should == 12345
    results.to_a.last.attributes['date'].to_i.should == 2
    
    table.items[12345, 1].delete()
    table.items[12345, 1].attributes['id'].should be_nil

    puts "Done"
        
  end  
end
