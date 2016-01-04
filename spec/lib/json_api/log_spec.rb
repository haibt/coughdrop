require 'spec_helper'

describe JsonApi::Log do
  it "should have defined pagination defaults" do
    expect(JsonApi::Log::TYPE_KEY).to eq('log')
    expect(JsonApi::Log::DEFAULT_PAGE).to eq(10)
    expect(JsonApi::Log::MAX_PAGE).to eq(25)
  end

  describe "build_json" do
    it "should not include unlisted settings" do
      l = LogSession.new(data: {'hat' => 'black'})
      expect(JsonApi::Log.build_json(l).keys).not_to be_include('hat')
    end

    it "should include appropriate values" do
      l = LogSession.new(data: {'hat' => 'black'}, started_at: Time.now, ended_at: Time.now)
      ['id', 'started_at', 'ended_at', 'summary'].each do |key|
        expect(JsonApi::Log.build_json(l).keys).to be_include(key)
      end
    end
    
    it "should return fake author information if there is no author" do
      u = User.create
      l = LogSession.new(data: {'hat' => 'black'}, started_at: Time.now, ended_at: Time.now)
      json = JsonApi::Log.build_json(l)
      expect(json['author']).not_to eq(nil)
      expect(json['author']['user_name']).to eq('unknown')
      expect(json['author']['id']).to eq(nil)
    end
    
    it "should return real author information if there is an author" do
      u = User.create
      l = LogSession.new(author: u, data: {'hat' => 'black'}, started_at: Time.now, ended_at: Time.now)
      json = JsonApi::Log.build_json(l)
      expect(json['author']).not_to eq(nil)
      expect(json['author']['user_name']).to eq(u.user_name)
      expect(json['author']['id']).to eq(u.global_id)
    end
        
    it "should include either not or log duration information" do
      l = LogSession.new(data: {'hat' => 'black'}, started_at: Time.now, ended_at: Time.now)
      l.data['note'] = 'hello'
      expect(JsonApi::Log.build_json(l).keys).to be_include('note')
      expect(JsonApi::Log.build_json(l).keys).not_to be_include('duration')
      
      l.data['note'] = nil
      expect(JsonApi::Log.build_json(l).keys).not_to be_include('note')
      expect(JsonApi::Log.build_json(l).keys).to be_include('duration')
      expect(JsonApi::Log.build_json(l).keys).to be_include('button_count')
      expect(JsonApi::Log.build_json(l).keys).to be_include('utterance_count')
      expect(JsonApi::Log.build_json(l).keys).to be_include('utterance_word_count')
    end
  end
  
  describe "extra_includes" do
    it "should include the events attribute" do
      l = LogSession.new(data: {'hat' => 'black'}, started_at: Time.now, ended_at: Time.now)
      json = JsonApi::Log.as_json(l, :wrapper => true)
      expect(json['log']['events']).to eql([])
    end
    
    it "should include the device" do
      l = LogSession.new(:log_type => 'session', data: {'hat' => 'black'}, started_at: Time.now, ended_at: Time.now)
      json = JsonApi::Log.as_json(l, :wrapper => true)
      expect(json['log']['device']).to eql({
        'id' => nil,
        'name' => 'Unknown device'
      })
    end
    
    it "should include data for known event types" do
      l = LogSession.new(data: {'hat' => 'black'}, started_at: Time.now, ended_at: Time.now)
#       entry = {}
#       entry['id'] = event['id']
#       entry['timestamp'] = event['timestamp']
#       entry['spoken'] = event['spoken']
#       if event['button']
#         entry['type'] = 'button'
#         entry['summary'] = event['button']['label']
#         entry['parts_of_speech'] = event['parts_of_speech']
#         if event['button']['percent_x'] && event['button']['percent_y'] && event['button']['board']
#           entry['touch_percent_x'] = event['button']['percent_x']
#           entry['touch_percent_y'] = event['button']['percent_y']
#           entry['board'] = event['button']['board']
#         end
#       elsif event['action']
#         entry['type'] = 'action'
#         entry['summary'] = "[#{event['action']['action']}]"
#         if event['action']['action'] == 'open_board'
#           entry['new_board'] = event['action']['new_id']
#         end
#       elsif event['utterance']
#         entry['type'] = 'utterance'
#         entry['summary'] = "[vocalize]"
#       else
#         entry['type'] = 'other'
#         entry['summary'] = "unrecognized event"
#       end
#       if event['notes']
#         entry['notes'] = event['notes'].map do |n|
#           {
#             'id' => n['id'],
#             'note' => n['note'],
#             'author' => {
#               'id' => n['author']['id'],
#               'user_name' => n['author']['user_name']
#             }
#           }
#         end
#       end
#       json['log']['events'] << entry
      l.data['events'] = [
        {'id' => 1, 'timestamp' => 12345, 'button' => {'spoken' => true, 'label' => 'hat'}, 'parts_of_speech' => {}},
        {'id' => 2, 'timestamp' => 12346, 'button' => {'label' => 'hat', 'percent_x' => 0.5, 'percent_y' => 0.32, 'board' => {}}, 'parts_of_speech' => {}},
        {'id' => 3, 'timestamp' => 12347, 'action' => {'action' => 'open_board', 'new_id' => {}}},
        {'id' => 4, 'timestamp' => 12348, 'action' => {'action' => 'auto_home'}},
        {'id' => 5, 'timestamp' => 12349, 'utterance' => {'spoken' => true, }},
        {'id' => 6, 'timestamp' => 12350},
        {'id' => 7, 'timestamp' => 12351, 'notes' => [
          {'id' => 1, 'note' => 'happy', 'author' => {}},
          {'id' => 2, 'note' => 'sad', 'author' => {'id' => '123'}}
        ]},
      ]
      json = JsonApi::Log.as_json(l, :wrapper => true)
      expect(json['log']['events'].length).to eql(7)
      expect(json['log']['events'][0]).to eql({
        'id' => 1,
        'parts_of_speech' => {},
        'spoken' => true,
        'summary' => 'hat',
        'timestamp' => 12345,
        'type' => 'button'
      })
      expect(json['log']['events'][1]).to eql({
        'id' => 2,
        'parts_of_speech' => {},
        'spoken' => false,
        'summary' => 'hat',
        'timestamp' => 12346,
        'type' => 'button',
        'board' => {},
        'touch_percent_x' => 0.5,
        'touch_percent_y' => 0.32
      })
      expect(json['log']['events'][2]).to eql({
        'id' => 3,
        'summary' => '[open_board]',
        'new_board' => {},
        'timestamp' => 12347,
        'type' => 'action'
      })
      expect(json['log']['events'][3]).to eql({
        'id' => 4,
        'summary' => '[auto_home]',
        'timestamp' => 12348,
        'type' => 'action'
      })
      expect(json['log']['events'][4]).to eql({
        'id' => 5,
        'summary' => '[vocalize]',
        'timestamp' => 12349,
        'type' => 'utterance'
      })
      expect(json['log']['events'][5]).to eql({
        'id' => 6,
        'summary' => 'unrecognized event',
        'timestamp' => 12350,
        'type' => 'other'
      })
      expect(json['log']['events'][6]).to eql({
        'id' => 7,
        'summary' => 'unrecognized event',
        'timestamp' => 12351,
        'type' => 'other',
        'notes' => [
          {
            'id' => 1,
            'note' => 'happy',
            'author' => {'id' => nil, 'user_name' => nil}
          },
          {
            'id' => 2,
            'note' => 'sad',
            'author' => {'id' => '123', 'user_name' => nil}
          }
        ]
      })
    end
    
    it "should include next_log_id and previous_log_id if found" do
      u = User.create
      d = Device.create(:user => u)
      l = LogSession.new(data: {'hat' => 'black'}, started_at: Time.now, ended_at: Time.now, :user => u, :device => d, :author => u)
      json = JsonApi::Log.as_json(l, :wrapper => true)
      expect(json['log']['new_log_id']).to eql(nil)
      expect(json['log']['previous_log_id']).to eql(nil)
      
      l.user = u
      l.save!
      LogSession.where(:id => l.id).update_all(:started_at => 2.hours.ago)
      l_pre = LogSession.create(:user => u)
      LogSession.where(:id => l_pre.id).update_all(:started_at => 3.hours.ago)
      l_post = LogSession.create(:user => u)
      LogSession.where(:id => l_post.id).update_all(:started_at => 1.hour.ago)
      l.reload
      json = JsonApi::Log.as_json(l, :wrapper => true)
      expect(json['log']['next_log_id']).to eql(l_post.global_id)
      expect(json['log']['previous_log_id']).to eql(l_pre.global_id)
    end
  end
  
end
