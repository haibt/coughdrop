require 'spec_helper'
require 'rack/test'

describe "throttling URLs" do
  include  Rack::Test::Methods
  
  def app
    Coughdrop::Application
  end
  
  def response
    last_response
  end
  
  before(:each) do
    Rack::Attack.cache.store.scan_each do |key|
      Rack::Attack.cache.store.del(key) if key
    end
  end

  
  def aggressive_throttle_check(request, success)
    (Throttling::PROTECTED_CUTOFF + 10).times do |i|
      request.call
      if i < Throttling::PROTECTED_CUTOFF - 2
        success.call
      elsif i > Throttling::PROTECTED_CUTOFF + 2
        expect(response.status).to eq(429)
        expect(response.body).to eq("Retry later\n")
      end
    end
  end
  
  def medium_throttle_check(request, success)
    (Throttling::TOKEN_CUTOFF + 20).times do |i|
      request.call
      if i < Throttling::TOKEN_CUTOFF - 2
        success.call
      elsif i > Throttling::TOKEN_CUTOFF + 2
        expect(response.status).to eq(429)
        expect(response.body).to eq("Retry later\n")
      end
    end
  end
  
  def conservative_throttle_check(request, success)
    (Throttling::NORMAL_CUTOFF + 50).times do |i|
      request.call
      if i < Throttling::NORMAL_CUTOFF - 2
        success.call
      elsif i > Throttling::NORMAL_CUTOFF + 2
        expect(response.status).to eq(429)
        expect(response.body).to eq("Retry later\n")
      end
    end
  end
  
  describe "/" do
    it "should throttle conservatively" do
      conservative_throttle_check(->{
        get "/"
      }, ->{
        expect(response.status).to eq(200)
        expect(response.body).to match(/CoughDrop/)
      })
    end
  end
  
  describe "POST /token" do
    it "should throttle aggressively" do
      token = Security.browser_token
      u = User.new(:user_name => "fred")
      u.generate_password("seashell")
      u.save
      medium_throttle_check(->{
        post "/token", {:grant_type => 'password', :client_id => 'browser', :client_secret => token, :username => 'fred', :password => 'seashell'}, 'REMOTE_ADDR' => '1.2.3.4'
      }, ->{
        expect(response.status).to eq(200)
        json = JSON.parse(response.body)
        expect(json['user_name']).to eq('fred')
      })
    end
  end
  
  describe "POST /api/v1/boards/\w+/download" do
    it "should throttle aggressiely" do
      u = User.create
      b = Board.create(:user => u, :public => true)
      aggressive_throttle_check(->{
        post "/api/v1/boards/#{b.key}/download", {:board_id => b.global_id}, {'REMOTE_ADDR' => '1.2.3.4'}
      }, ->{
        expect(response.status).to eq(200)
        json = JSON.parse(response.body)
        expect(json['progress']['id']).not_to eq(nil)
      })
    end
  end
  
  describe "POST /api/v1/purchase_gift" do
    it "should throttle aggressively" do
      @user = User.create
      @device = Device.create(:user => @user, :developer_key_id => 1, :device_key => 'hippo')
      p = Progress.create
      expect(Progress).to receive(:schedule).with(GiftPurchase, :process_subscription_token, {'id' => 'abc'}, {'type' => 'long_term_150', 'email' => nil, 'user_id' => @user.global_id}).and_return(p).exactly(10).times
      aggressive_throttle_check(->{
        header 'Authorization', "Bearer #{@device.token}"
        header 'Check-Token', 'true'
        post "/api/v1/purchase_gift", {:token => {'id' => 'abc'}, :type => 'long_term_150'}, {'REMOTE_ADDR' => '1.2.3.4'}
      }, ->{
        expect(response.status).to eq(200)
        json = JSON.parse(response.body)
        expect(json['progress']).not_to eq(nil)
      })
    end
  end
end
