require 'spec_helper'

describe JsonApi::Board do
  it "should have defined pagination defaults" do
    expect(JsonApi::Board::TYPE_KEY).to eq('board')
    expect(JsonApi::Board::DEFAULT_PAGE).to eq(25)
    expect(JsonApi::Board::MAX_PAGE).to eq(50)
  end

  describe "build_json" do
    it "should not include unlisted settings" do
      u = User.create
      b = Board.create(:user => u)
      b.settings['hat'] = 'black'
      expect(JsonApi::Board.build_json(b).keys).not_to be_include('hat')
    end
    
    it "should return appropriate attributes" do
      u = User.create
      b = Board.create(:user => u)
      ['id', 'key', 'public', 'user_name'].each do |key|
        expect(JsonApi::Board.build_json(b).keys).to be_include(key)
      end
    end
    
    it "should include permissions and stars if permissions are requested" do
      u = User.create
      b = Board.create(:user => u)
      expect(JsonApi::Board.build_json(b, :permissions => u)['permissions']).to eq({'user_id' => u.global_id, 'view' => true, 'edit' => true, 'delete' => true, 'share' => true})
      expect(JsonApi::Board.build_json(b, :permissions => u)['starred']).to eq(false)
    end
  end
  
  describe "extra_includes" do
    it "should include linked images and sounds" do
      u = User.create
      b = Board.create(:user => u)
      hash = JsonApi::Board.extra_includes(b, {})
      expect(hash['images']).to eq([])
      expect(hash['sounds']).to eq([])
      
      hash = JsonApi::Board.as_json(b, :wrapper => true)
      expect(hash['images']).to eq([])
      expect(hash['sounds']).to eq([])
      
      i = ButtonImage.create
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'parasol', 'image_id' => i.global_id}
      ]
      b.instance_variable_set('@buttons_changed', true)
      b.save
      expect(b.button_images.count).to eq(1)
      
      hash = JsonApi::Board.as_json(b.reload, :wrapper => true)
      expect(hash['images'].length).to eq(1)
      expect(hash['images'][0]['id']).to eq(i.global_id)
      expect(hash['sounds']).to eq([])
    end
    
    it "should include copy information if any for the current user" do
      u = User.create
      b = Board.create(:user => u)
      u2 = User.create
      
      hash = JsonApi::Board.as_json(b, :permissions => u2, :wrapper => true)
      expect(hash['board']['copy']).to eq(nil)
      
      b2 = Board.create(:user => u2, :parent_board_id => b.id)
      hash = JsonApi::Board.as_json(b, :permissions => u2, :wrapper => true)
      expect(hash['board']['copy']).to eq({
        'id' => b2.global_id,
        'key' => b2.key
      })
    end
    
    it "should include original-board information if any for the current board" do
      u = User.create
      b = Board.create(:user => u)
      u2 = User.create
      
      hash = JsonApi::Board.as_json(b, :permissions => u2, :wrapper => true)
      expect(hash['board']['copy']).to eq(nil)
      
      b2 = Board.create(:user => u2, :parent_board_id => b.id)
      hash = JsonApi::Board.as_json(b2, :permissions => u2, :wrapper => true)
      expect(hash['board']['original']).to eq({
        'id' => b.global_id,
        'key' => b.key
      })
    end
  end
end
