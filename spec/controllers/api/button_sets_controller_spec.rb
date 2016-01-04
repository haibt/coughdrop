require 'spec_helper'

describe Api::ButtonSetsController, :type => :controller do
  describe "show" do
    it "should require api token" do
      get :show, :id => 'asdf'
      assert_missing_token
    end
    
    it "should require existing object" do
      token_user
      get :show, :id => '1_19999'
      assert_not_found
    end

    it "should require authorization" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      bs = BoardDownstreamButtonSet.update_for(b.global_id)
      get :show, :id => b.global_id
      assert_unauthorized
    end
    
    it "should return a json response" do
      token_user
      b = Board.create(:user => @user)
      bs = BoardDownstreamButtonSet.update_for(b.global_id)
      get :show, :id => b.global_id
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['buttonset']['id']).to eq(b.global_id)
      expect(json['buttonset']['buttons']).to eq([])
    end
  end
end
