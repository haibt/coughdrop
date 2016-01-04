require 'spec_helper'

describe ButtonImage, :type => :model do
  describe "paper trail" do
    it "should make sure paper trail is doing its thing"
  end
  
  describe "permissions" do
    it "should have some permissions set" do
      i = ButtonImage.new
      expect(i.permissions_for(nil)).to eq({'user_id' => nil, 'view' => true})
      u = User.create
      i.user = u
      expect(i.permissions_for(u)).to eq({'user_id' => u.global_id, 'view' => true, 'edit' => true})
      u2 = User.create
      User.link_supervisor_to_user(u2, u)
      i.user.reload
      expect(i.permissions_for(u2.reload)).to eq({'user_id' => u2.global_id, 'view' => true, 'edit' => true})
    end
  end
  
  describe "generate_defaults" do
    it "should generate default values" do
      i = ButtonImage.new
      i.generate_defaults
      expect(i.settings['license']).to eq({'type' => 'private'})
      expect(i.public).to eq(false)
    end
    
    it "should not override existing values" do
      i = ButtonImage.new(public: true, settings: {'license' => {'type' => 'nunya'}})
      i.generate_defaults
      expect(i.settings['license']).to eq({'type' => 'nunya'})
      expect(i.public).to eq(true)
    end
  end

  describe "track_image_use" do
    it "shouldn't track if there is a suggestion (system picked the icon) or there isn't a label or search term" do
      expect(ButtonImage).not_to receive(:track_image_use)
      i = ButtonImage.new(settings: {
        'suggestion' => 'abc'
      })
      i.track_image_use
      i.settings = {
        'hat' => true
      }
      i.track_image_use
    end
    
    it "shouldn't track if there is no board set" do
      u = User.create
      i = ButtonImage.new(settings: {
        'suggestion' => 'abc'
      }, :user => u)
      i.track_image_use
      i.settings = {
        'hat' => true
      }
      i.track_image_use
    end
    
    it "shouldn't track if the set board isn't public" do
      u = User.create
      b = Board.create(:user => u)
      i = ButtonImage.new(settings: {
        'suggestion' => 'abc'
      }, :user => u, :board => b)
      i.track_image_use
      i.settings = {
        'hat' => true
      }
      i.track_image_use
    end
    
    it "should use image settings if available" do
      u = User.create
      b = Board.create(:user => u, :public => true)
      i = ButtonImage.new(settings: {
        'search_term' => 'bacon',
        'label' => 'pig'
      }, user: u, board: b)
      expect(ButtonImage).to receive(:track_image_use).with({
        :search_term => 'bacon',
        :label => 'pig',
        :suggestion => nil,
        :external_id => nil,
        :user_id => u.global_id
      })
      i.track_image_use
    end
    
    it "should make an API call to opensymbols" do
      u = User.create
      b = Board.create(:user => u, :public => true)
      i = ButtonImage.new(settings: {
        'search_term' => 'bacon',
        'label' => 'pig',
        'external_id' => '12356'
      }, user: u, board: b)
      expect(Typhoeus).to receive(:post) do |url, args|
        expect(url).to eq("https://opensymbols.herokuapp.com/api/v1/symbols/12356/use")
        expect(args[:body][:access_token]).not_to eq(nil)
        expect(args[:body][:user_id]).not_to eq(nil)
      end
      i.track_image_use
    end
    
    it "should schedule call to track_image_use" do
      u = User.create
      b = Board.create(:user => u, :public => true)
      i = ButtonImage.new(settings: {
        'search_term' => 'bacon',
        'label' => 'pig',
        'external_id' => '12356'
      }, user: u, board: b)
      i.save
      expect(Typhoeus).to receive(:post) do |url, args|
        expect(url).to eq("https://opensymbols.herokuapp.com/api/v1/symbols/12356/use")
        expect(args[:body][:user_id]).not_to eq(nil)
        expect(args[:body][:user_id]).not_to eq(u.id)
        expect(args[:body][:user_id]).not_to eq(u.global_id)
        expect(args[:body][:user_id].length).to eq(10)
      end
      Worker.process_queues
    end

    it "should obfuscate user_id" do
      u = User.create
      b = Board.create(:user => u, :public => true)
      i = ButtonImage.new(settings: {
        'search_term' => 'bacon',
        'label' => 'pig',
        'external_id' => '12356'
      }, user: u, board: b)
      expect(Typhoeus).to receive(:post) do |url, args|
        expect(url).to eq("https://opensymbols.herokuapp.com/api/v1/symbols/12356/use")
        expect(args[:body][:user_id]).not_to eq(nil)
        expect(args[:body][:user_id]).not_to eq(u.id)
        expect(args[:body][:user_id]).not_to eq(u.global_id)
        expect(args[:body][:user_id].length).to eq(10)
      end
      i.track_image_use
    end
  end

  describe "process_params" do
    it "should ignore unspecified parameters" do
      i = ButtonImage.new(:user_id => 1)
      expect(i.process_params({}, {})).to eq(true)
    end
    
    it "should raise if no user set" do
      i = ButtonImage.new
      expect { i.process_params({}, {}) }.to raise_error("user required as image author")
    end
    
    it "should set parameters" do
      u = User.new
      i = ButtonImage.new(:user_id => 1)
      expect(i.process_params({
        'content_type' => 'image/png',
        'suggestion' => 'hat',
        'public' => true
      }, {
        :user => u
      })).to eq(true)
      expect(i.settings['content_type']).to eq('image/png')
      expect(i.settings['license']).to eq(nil)
      expect(i.settings['suggestion']).to eq('hat')
      expect(i.settings['search_term']).to eq(nil)
      expect(i.settings['external_id']).to eq(nil)
      expect(i.public).to eq(true)
      expect(i.user).to eq(u)
    end
    
    it "should process the URL including non_user_params if sent" do
      u = User.new
      i = ButtonImage.new(:user_id => 1)
      expect(i.process_params({
        'url' => 'http://www.example.com'
      }, {})).to eq(true)
      expect(i.settings['url']).to eq(nil)
      expect(i.settings['pending_url']).to eq('http://www.example.com')
    end
  end
   
  it "should securely serialize settings" do
    expect(SecureJson).to receive(:dump).with({:a=>1, "pending"=>true, "license"=>{"type"=>"private"}})
    ButtonImage.create(:settings => {:a => 1})
  end
  
  it "should remove from remote storage if no longer in use" do
    u = User.create
    i = ButtonImage.create(:user => u)
    i.removable = true
    i.url = "asdf"
    i.settings['full_filename'] = "asdf"
    expect(Uploader).to receive(:remote_remove).with("asdf")
    i.destroy
    Worker.process_queues
  end
end
