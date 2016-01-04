require 'spec_helper'

describe Api::ProgressController, :type => :controller do
  describe "progress" do
    it "should not require api token" do
      get :progress, :id => 'abc'
      assert_not_found
    end

    it "should error on not found" do
      token_user
      get :progress, :id => 'abc'
      assert_not_found
    end
    
    it "should return a progress object if found" do
      token_user
      p = Progress.create
      get :progress, :id => p.global_id
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['progress']['id']).to eq(p.global_id)
      expect(json['progress']['status']).to eq('pending')
    end
  end
end
