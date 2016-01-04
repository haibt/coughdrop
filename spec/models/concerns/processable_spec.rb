require 'spec_helper'

describe Processable, :type => :model do
  class FakeRecord
    include Processable
  end
  describe "process" do
    it "should call process_params" do
      r = FakeRecord.new
      expect(r).to receive(:process_params).with({}, {})
      expect(r).to receive(:save)
      r.process({})
    end
    
    it "should indifferent_access the arguments" do
      r = FakeRecord.new
      expect(r).to receive(:process_params) do |params, non_user_params|
        expect(params['a']).to eq(1)
        expect(params['b']).to eq(nil)
        expect(non_user_params['b']).to eq(2)
      end
      expect(r).to receive(:save)
      r.process({:a => 1}, {:b => 2})
    end
    
    it "should not call save if process_params returns false" do
      r = FakeRecord.new
      expect(r).to receive(:process_params).with({}, {}).and_return(false)
      expect(r).not_to receive(:save)
      r.process({})
    end
  end
  
  describe "clean_path" do
    it "should not allow starting with a number" do
      r = FakeRecord.new
      expect(r.clean_path("12345")).to eq("_12345")
      expect(r.clean_path("1awgweg")).to eq("_1awgweg")
    end
    
    it "should remove apostophes" do
      r = FakeRecord.new
      expect(r.clean_path("bob's stuff")).to eq("bobs-stuff")
      expect(r.clean_path("'a'b'c'_'e")).to eq("abc_e")
    end
    
    it "should enforce minimum length of 4" do
      r = FakeRecord.new
      expect(r.clean_path("a")).to eq("aaa")
      expect(r.clean_path("ac")).to eq("acac")
      expect(r.clean_path("d")).to eq("ddd")
      expect(r.clean_path("bob")).to eq("bob")
      expect(r.clean_path("fred")).to eq("fred")
    end
    
    it "should substitute chains of extra characters with a hyphen" do
      r = FakeRecord.new
      expect(r.clean_path("a boy")).to eq("a-boy")
      expect(r.clean_path("a a a")).to eq("a-a-a")
      expect(r.clean_path("a     ")).to eq("aaa")
      expect(r.clean_path("a**#&@%#@*")).to eq("aaa")
      expect(r.clean_path("a**#b&@%#@*")).to eq("a-b")
      expect(r.clean_path("bob! I really like descriptions! Don't you?!?")).to eq("bob-i-really-like-descriptions-dont-you")
      expect(r.clean_path("-----abc__def")).to eq("-abc__def")
    end
    
  end

  describe "generate_unique_key" do
    class FakeRecord
      include Processable
    end
    
    it "should raise an error if called for an unknown class" do
      r = FakeRecord.new
      expect { r.generate_unique_key("bob") }.to raise_error("unknown class: FakeRecord")
    end
  end

  describe "generate_user_name" do
    it "should generate a user name" do
      u = User.new
      expect(u.generate_user_name).to eq('person')
    end
    
    it "should fall back to the user's full name if nothing else provided" do
      u = User.new(:settings => {'name' => 'Bob Jones'})
      expect(u.generate_user_name).to eq('bob-jones')
    end
    
    it "should not generate an existing user name" do
      User.create(:user_name => "franklin")
      u = User.new
      expect(u.generate_user_name("franklin")).to eq("franklin_1")
    end
    
    it "should smartly change numbers until it find a unique user name" do
      User.create(:user_name => "franklin")
      User.create(:user_name => "franklin_1")
      User.create(:user_name => "franklin_2")
      User.create(:user_name => "franklin_3")
      u = User.new
      expect(u.generate_user_name("franklin")).to eq("franklin_4")
      expect(u.generate_user_name("franklin_1")).to eq("franklin_4")
    end
    
    it "should not allow usernames for reserved routes" do
      u = User.new
      expect(u.generate_user_name("admin")).to eq("admin_1")
      expect(u.generate_user_name("oauth")).to eq("oauth_1")
      expect(u.generate_user_name("about")).to eq("about_1")
      expect(u.generate_user_name("pages")).to eq("pages_1")
      
    end
  end  

  describe "generate_board_key" do
    it "should raise an error if no user is provided" do
      b = Board.new
      expect { b.generate_board_key }.to raise_error("user required")
    end
    
    it "should generate a board key based on the user and board information" do
      u = User.new(:user_name => "melinda")
      b = Board.new(:user => u)
      expect(b.generate_board_key).to eq("melinda/board")
    end
    
    it "should fall back to the board's name if no key provided" do
      u = User.new(:user_name => "melinda")
      b = Board.new(:user => u, :settings => {'name' => 'my awesome board!'})
      expect(b.generate_board_key).to eq("melinda/my-awesome-board")
    end
    
    it "should not generate an existing board key" do
      u = User.new(:user_name => "melinda")
      Board.create(:user => u, :settings => {'name' => 'bacon'})
      b = Board.new(:user => u)
      expect(b.generate_board_key('bacon')).to eq("melinda/bacon_1")
    end
    
    it "should smartly change numbers until it finds a unique board key" do
      u = User.new(:user_name => "melinda")
      Board.create(:user => u, :settings => {'name' => 'bacon'})
      Board.create(:user => u, :settings => {'name' => 'bacon'})
      Board.create(:user => u, :settings => {'name' => 'bacon'})
      Board.create(:user => u, :settings => {'name' => 'bacon'})
      b = Board.new(:user => u)
      expect(b.generate_board_key('bacon')).to eq("melinda/bacon_4")
      expect(b.generate_board_key('bacon_2')).to eq("melinda/bacon_4")
    end
  end  

  describe "process_new" do
    it "should instantiate and call process" do
      expect_any_instance_of(FakeRecord).to receive(:process).with({'a' => 1}, {'b' => 2})
      FakeRecord.process_new({'a' => 1}, {'b' => 2})
    end
  end
end
