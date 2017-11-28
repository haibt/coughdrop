require 'spec_helper'

describe JsonApi::User do
  it "should have defined pagination defaults" do
    expect(JsonApi::User::TYPE_KEY).to eq('user')
    expect(JsonApi::User::DEFAULT_PAGE).to eq(25)
    expect(JsonApi::User::MAX_PAGE).to eq(50)
  end

  describe "build_json" do
    it "should not include unlisted settings" do
      u = User.create(settings: {'hat' => 'black'})
      expect(JsonApi::User.build_json(u).keys).not_to be_include('hat')
    end
    
    it "should include appropriate attributes" do
      u = User.create(settings: {'hat' => 'black'})
      ['id', 'user_name', 'avatar_url'].each do |key|
        expect(JsonApi::User.build_json(u).keys).to be_include(key)
      end
    end
    
    it "should include a correct gravatar url if profile is visible" do
      u = User.create(settings: {'email' => 'bob@example.com', 'public' => true})
      expect(JsonApi::User.build_json(u)['avatar_url']).to match(/https:\/\/www\.gravatar\.com\/avatar\/4b9bb80620f03eb3719e0a061c14283d/)
    end
    
    it "should include a silhouette url if profile is not visible" do
      u = User.create(settings: {'email' => 'bob@example.com'})
      expect(JsonApi::User.build_json(u)['avatar_url']).to match(/https:\/\/s3\.amazonaws\.com\/coughdrop\/avatars\/avatar-\d\.png/)
    end

    it "should include permissions if requested" do
      u = User.create(settings: {'email' => 'bob@example.com'})
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['permissions']).to eq({'user_id' => u.global_id, 'view_existence' => true, 'view_detailed' => true, 'view_word_map' => true, 'supervise' => true, 'manage_supervision' => true, 'edit' => true, 'delete' => true, 'view_deleted_boards' => true})
      
      hash = expect(JsonApi::User.build_json(u, permissions: nil)['permissions']).to eq({'user_id' => nil, 'view_existence' => true})
    end
    
    it "should include membership information only if edit priveleges are available" do
      u = User.create(:settings => {'public' => true})
      json = JsonApi::User.build_json(u, permissions: nil)
      expect(json['membership_type']).to eq('premium')
      
      json = JsonApi::User.build_json(u, permissions: u)
      expect(json['membership_type']).to eq('premium')
      
      u.settings['public'] = false
      u.updated_at = Time.now
      json = JsonApi::User.build_json(u, permissions: nil)
      expect(json['membership_type']).to eq(nil)
    end
    
    it "should include premium voices if any are available" do
      u = User.create(:settings => {'premium_voices' => {'claimed' => ['abc', 'bcd']}})
      json = JsonApi::User.build_json(u, permissions: nil)
      expect(json['premium_voices']).to eq(nil)

      json = JsonApi::User.build_json(u, permissions: u)
      expect(json['premium_voices']).to eq({'claimed' => ['abc', 'bcd']})
      
      u.settings['premium_voices'] = nil
      json = JsonApi::User.build_json(u, permissions: u)
      expect(json['premium_voices']).to eq({'claimed' => [], 'allowed' => 0})
    end
    
    it "should include board ids if the user has set a home board" do
      u = User.create
      b = Board.create(:user => u)
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['stats']['board_set_ids'].length).to eq(0)
      
      u.settings['preferences'] = {'home_board' => {'id' => b.global_id}}
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['stats']['board_set_ids'].length).to eq(1)
      expect(hash['preferences']['home_board']).to eq({'id' => b.global_id})
      
      u.settings['starred_board_ids'] = ["4_1", b.global_id]
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['stats']['board_set_ids'].length).to eq(1)
    end
    
    it "should include supervisee board ids if the user has any" do
      u = User.create
      b = Board.create(:user => u)
      u2 = User.create
      b2 = Board.create(:user => u2)
      
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['stats']['board_set_ids'].length).to eq(0)
      
      u.settings['preferences'] = {'home_board' => {'id' => b.global_id}}
      u.save
      u2.settings['preferences'] = {'home_board' => {'id' => b2.global_id}}
      u2.save
      
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['stats']['board_set_ids'].length).to eq(1)
      expect(hash['stats']['board_set_ids_including_supervisees'].length).to eq(1)
      
      u.settings['starred_board_ids'] = ["4_1", b.global_id]
      u.save
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['stats']['board_set_ids'].length).to eq(1)
      expect(hash['stats']['board_set_ids_including_supervisees'].length).to eq(1)

      User.link_supervisor_to_user(u, u2)
      u.reload
      u2.reload
      expect(u.supervisees).to eq([u2])
      
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['stats']['board_set_ids'].length).to eq(1)
      expect(hash['stats']['board_set_ids_including_supervisees'].length).to eq(2)
    end
    
    it "should fall back to default device settings if none for the current device" do
      u = User.create
      u.settings['preferences']['devices']['default'] = {'a' => 1}
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['preferences']).not_to eq(nil)
      expect(hash['preferences']['device']).to eq({'a' => 1, 'voice' => {}, 'alternate_voice' => {}, 'ever_synced' => false})
    end
    
    it "should merge device settings with the default settings" do
      u = User.create
      d = Device.create(:user => u, :developer_key_id => 0, :device_key => "1.2532 Stubborn Child")
      u.settings['preferences']['devices']['default'] = {'a' => 1}
      u.settings['preferences']['devices'][d.unique_device_key] = {'b' => 3}
      hash = JsonApi::User.build_json(u, permissions: u, device: d)
      expect(hash['preferences']).not_to eq(nil)
      expect(hash['preferences']['device']).to eq({'b' => 3, 'name' => 'Stubborn Child', 'voice' => {}, 'alternate_voice' => {}, 'ever_synced' => false})
    end
    
    it "should find the most-recent matching device and fall back to those settings rather than default if available" do
      u = User.create
      d = Device.create(:user => u, :developer_key_id => 0, :device_key => "1.2532 Stubborn Child")
      d2 = Device.create(:user => u, :developer_key_id => 0, :device_key => "1.253522 Stubborn Child")
      d2.settings['token_history'] = [1,2,3,4]
      d2.save
      u.settings['preferences']['devices']['default'] = {'a' => 1}
      u.settings['preferences']['devices'][d.unique_device_key] = {'b' => 3}
      u.settings['preferences']['devices'][d2.unique_device_key] = {'c' => 3}
      hash = JsonApi::User.build_json(u, permissions: u, device: d)
      expect(hash['preferences']).not_to eq(nil)
      expect(hash['preferences']['device']).to eq({'c' => 3, 'b' => 3, 'name' => 'Stubborn Child', 'voice' => {}, 'alternate_voice' => {}, 'ever_synced' => false})
    end
    
    it "should include prior home boards but not the current home board only when edit permission is available" do
      u = User.create(:settings => {'public' => true})
      u.settings['all_home_boards'] = [{'key' => 'bob/hat', 'id' => '1_3'}, {'key' => 'bob/cat', 'id' => '1_4'}]
      u.settings['preferences']['home_board'] = {'key' => 'bob/cat', 'id' => '1_4'}
      u.save
      json = JsonApi::User.build_json(u, permissions: nil)
      expect(json['prior_home_boards']).to eq(nil)
      
      json = JsonApi::User.build_json(u, permissions: u)
      expect(json['prior_home_boards']).to eq([{'key' => 'bob/hat', 'id' => '1_3'}])
    end

    it "should include manager status if organization specified" do
      u = User.create
      o = Organization.create
      o.add_manager(u.user_name)
      u.reload
      json = JsonApi::User.build_json(u, :limited_identity => true, :organization => o)
      expect(json['org_manager']).to eq(false)
      expect(json['org_assistant']).to eq(true)
    end
    
    describe "subscription" do
      it "should return a subscription object only when edit permission is available" do
        u = User.create
        json = JsonApi::User.build_json(u)
        expect(json['subscription']).to eq(nil)
        
        json = JsonApi::User.build_json(u, permissions: u)
        expect(json['subscription']).not_to eq(nil)
      end
      
      it "should return a subscription hash when admin_support_actions are allowed" do
        u = User.create
        u2 = User.create
        o = Organization.create(:admin => true)
        o.add_manager(u2.user_name, true)
        
        json = JsonApi::User.build_json(u, permissions: u2.reload)
        expect(json['subscription']).not_to eq(nil)
      end
      
      it "should return proper subscription attributes" do
        u = User.create
        o = Organization.create(:settings => {'total_licenses' => 1})
        u.settings['subscription'] = {}
        u.settings['subscription']['never_expires'] = true
        u.settings['subscription']['org_sponsored'] = true
        u.settings['subscription']['added_to_organization'] = 3.months.ago.iso8601
        u.expires_at = 2.weeks.from_now
        u.settings['subscription']['started'] = 6.months.ago.iso8601
        u.settings['subscription']['plan_id'] = 'monthly_6'
        
        json = JsonApi::User.build_json(u, permissions: u)
        expect(json['subscription']).to eq({
          'never_expires' => true,
          'active' => true
        })
        expect(u.expires_at).to_not eq(nil)
        
        o.add_user(u.user_name, false, true)
        u.reload
        expect(u.expires_at).to eq(nil)
        u.settings['subscription']['never_expires'] = false
        json = JsonApi::User.build_json(u, permissions: u)
        expect(json['subscription']).to eq({
          'active' => true,
        })
        
        o.remove_user(u.user_name)
        u.reload
        u.settings['subscription']['started'] = 6.months.ago.iso8601
        u.settings['subscription']['plan_id'] = 'monthly_6'
        json = JsonApi::User.build_json(u, permissions: u)
        expect(json['subscription']).to eq({
          'grace_period' => false,
          'active' => true,
          'expires' => u.expires_at.iso8601,
          'started' => u.settings['subscription']['started'],
          'plan_id' => 'monthly_6'
        })
        
        u.settings['subscription']['started'] = nil
        json = JsonApi::User.build_json(u, permissions: u)
        expect(json['subscription']).to eq({
          'grace_period' => true,
          'expires' => u.expires_at.iso8601
        })
        
        u.settings['subscription']['customer_id'] = 'bob'
        u.settings['subscription']['last_purchase_plan_id'] = 'long_term_100'
        json = JsonApi::User.build_json(u, permissions: u)
        expect(json['subscription']).to eq({
          'grace_period' => false,
          'active' => true,
          'expires' => u.expires_at.iso8601,
          'purchased' => true,
          'plan_id' => 'long_term_100'
        })
        
        u.settings['subscription']['never_expires'] = true
        json = JsonApi::User.build_json(u, permissions: u)
        expect(json['subscription']).to eq({
          'active' => true,
          'never_expires' => true
        })
      end
      
      it "should return a subscription object if explicitly specified" do
        u = User.create
        u2 = User.create
        o = Organization.create(:admin => true)
        o.add_manager(u2.user_name, true)
        
        json = JsonApi::User.build_json(u)
        expect(json['subscription']).to eq(nil)
        json = JsonApi::User.build_json(u, :limited_identity => true, :subscription => true)
        expect(json['subscription']).not_to eq(nil)
      end
      
      it "should include subscription object if include_subscription specified, even without limited_identity" do
        u = User.create
        u2 = User.create
        o = Organization.create(:admin => true)
        o.add_manager(u2.user_name, true)
        
        json = JsonApi::User.build_json(u)
        expect(json['subscription']).to eq(nil)
        json = JsonApi::User.build_json(u, :include_subscription => true)
        expect(json['subscription']).not_to eq(nil)
      end
    end
    
    describe "sidebar_boards" do
      it "should only return sidebar boards if supervise permission is enabled" do
        u = User.create
        hash = JsonApi::User.build_json(u)
        expect(hash['preferences']).to eq(nil)
        
        u.settings['public'] = true
        u.save
        hash = JsonApi::User.build_json(u)
        expect(hash['preferences']).to eq(nil)

        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['permissions']['supervise']).to eq(true)
        expect(hash['preferences']['sidebar_boards']).not_to eq(nil)        
      end
      
      it "should return a default set of sidebar boards if none are defined" do
        u = User.create
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['preferences']['sidebar_boards']).not_to eq(nil)
        expect(hash['preferences']['sidebar_boards'].length).to be > 0
      end
      
      it "should return a default set of sidebar boards if the defined list is empty" do
        u = User.create
        u.settings['preferences']['sidebar_boards'] = []
        u.save

        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['preferences']['sidebar_boards']).not_to eq(nil)
        expect(hash['preferences']['sidebar_boards'].length).to be > 0        
      end
    end

    describe "linked objects" do
      it "should include devices" do
        u = User.create
        d = Device.create(:device_key => 'abc', :user => u, :developer_key_id => 1)
        u.process({
          'preferences' => {
            'device' => {}
          }
        }, {'user' => u, 'device' => d})
        
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['permissions']['edit']).to eq(true)
        expect(hash['devices']).not_to eq(nil)
        expect(hash['devices'].length).to eq(1)
      end
      
      it "should not include hidden devices" do
        u = User.create
        d = Device.create(:device_key => 'abc', :user => u, :developer_key_id => 1)
        d.settings['hidden'] = true
        d.save
        d2 = Device.create(:device_key => 'abcd', :user => u, :developer_key_id => 1)
        u.process({
          'preferences' => {
            'device' => {}
          }
        }, {'user' => u, 'device' => d})
        
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['permissions']['edit']).to eq(true)
        expect(hash['devices']).not_to eq(nil)
        expect(hash['devices'].length).to eq(1)
        expect(hash['devices'][0]['id']).to eq(d2.global_id)
      end
      
      it "should include supervisors only if there are any" do
        u = User.create
        u2 = User.create
        u.settings['supervisors'] = [{'user_id' => u2.global_id}]
        hash = JsonApi::User.build_json(u)
        expect(hash['permissions']).to eq(nil)
        expect(hash['supervisors']).to eq(nil)
        
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['permissions']).not_to eq(nil)
        expect(hash['supervisors']).not_to eq(nil)
        expect(hash['supervisors'].length).to eq(1)
        expect(hash['supervisors'][0]['id']).to eq(u2.global_id)
        expect(hash['supervisors'][0]['name']).to eq(u2.settings['name'])
        expect(hash['supervisors'][0]['user_name']).to eq(u2.user_name)
        expect(hash['supervisors'][0]['edit_permission']).to eq(false)

        u.settings['supervisors'] = [{'user_id' => u2.global_id, 'edit_permission' => true}]
        u.save
        u2.settings['supervisees'] = [{'user_id' => u.global_id, 'edit_permission' => true}]
        u2.save

        expect(u2.edit_permission_for?(u)).to eq(true)
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['permissions']).not_to eq(nil)
        expect(hash['supervisors']).not_to eq(nil)
        expect(hash['supervisors'].length).to eq(1)
        expect(hash['supervisors'][0]['id']).to eq(u2.global_id)
        expect(hash['supervisors'][0]['name']).to eq(u2.settings['name'])
        expect(hash['supervisors'][0]['user_name']).to eq(u2.user_name)
        expect(hash['supervisors'][0]['edit_permission']).to eq(true)
        
        u.settings['supervisors'] = nil
        u.save
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['permissions']).not_to eq(nil)
        expect(hash['supervisors']).to eq(nil)
      end
      
      it "should include supervisees only if there are any" do
        u = User.create
        u2 = User.create
        u.settings['supervisees'] = [{'user_id' => u2.global_id}]
        hash = JsonApi::User.build_json(u)
        expect(hash['permissions']).to eq(nil)
        expect(hash['supervisees']).to eq(nil)
        
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['permissions']).not_to eq(nil)
        expect(hash['supervisees']).not_to eq(nil)
        expect(hash['supervisees'].length).to eq(1)
        expect(hash['supervisees'][0]['id']).to eq(u2.global_id)
        expect(hash['supervisees'][0]['name']).to eq(u2.settings['name'])
        expect(hash['supervisees'][0]['user_name']).to eq(u2.user_name)
        
        u.settings['supervisees'] = nil
        u.save
        hash = JsonApi::User.build_json(u.reload, permissions: u)
        expect(hash['permissions']).not_to eq(nil)
        expect(hash['supervisees']).to eq(nil)
      end
      
      it "should include org-added supervisees in paginated list if for an organization" do
        u = User.create
        u2 = User.create
        u3 = User.create
        User.link_supervisor_to_user(u, u2)
        User.link_supervisor_to_user(u, u3)
        o = Organization.create(:settings => {'total_licenses' => 4})
        o.add_supervisor(u.user_name, true)
        o.add_user(u2.user_name, false)
        
        list = JsonApi::User.paginate({}, [u.reload], {:limited_identity => true, :organization => o.reload, :prefix => '/asdf'})
        expect(list['user'].length).to eq(1)
        expect(list['user'][0]['org_supervision_pending']).to eq(true)
        expect(list['user'][0]['org_supervisees']).to eq(nil)
        expect(list['user'][0]['supervisees']).to eq(nil)
        
        o.add_supervisor(u.user_name, false)
        list = JsonApi::User.paginate({}, [u.reload], {:limited_identity => true, :organization => o.reload, :prefix => '/asdf'})
        expect(list['user'].length).to eq(1)
        expect(list['user'][0]['org_supervision_pending']).to eq(false)
        expect(list['user'][0]['supervisees']).to eq(nil)
        expect(list['user'][0]['org_supervisees']).to_not eq(nil)
        expect(list['user'][0]['org_supervisees'].length).to eq(1)
        expect(list['user'][0]['org_supervisees'][0]['user_name']).to eq(u2.user_name)
      end
    end
    
    it "should include any pending board shares" do
      u = User.create
      u2 = User.create
      b = Board.create(:user => u2)
      b.share_with(u, true, true)
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['pending_board_shares']).to_not eq(nil)
      expect(hash['pending_board_shares'].length).to eq(1)
      expect(hash['pending_board_shares'][0]['board_id']).to eq(b.global_id)
    end
    
    describe "organizations" do
      it "should include any managing organization" do
        o = Organization.create(:settings => {'total_licenses' => 2})
        u = User.create
        o.add_user(u.user_name, true, true)
        u.reload
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['organizations'].length).to eq(1)
        expect(hash['organizations'][0]['id']).to eq(o.global_id)
        expect(hash['organizations'][0]['type']).to eq('user')
        expect(hash['organizations'][0]['pending']).to eq(true)
        expect(hash['organizations'][0]['sponsored']).to eq(true)
        
        o.add_user(u.user_name, false, false)
        u.reload
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['organizations'].length).to eq(1)
        expect(hash['organizations'][0]['id']).to eq(o.global_id)
        expect(hash['organizations'][0]['type']).to eq('user')
        expect(hash['organizations'][0]['pending']).to eq(false)
        expect(hash['organizations'][0]['sponsored']).to eq(false)
      end
      
      it "should include any managed organizations" do
        o = Organization.create(:settings => {'total_licenses' => 2})
        o2 = Organization.create(:settings => {'total_licenses' => 2})
        u = User.create
        o.add_manager(u.user_name, true)
        u.reload
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['organizations'].length).to eq(1)
        expect(hash['organizations'][0]['id']).to eq(o.global_id)
        expect(hash['organizations'][0]['type']).to eq('manager')
        expect(hash['organizations'][0]['full_manager']).to eq(true)
        
        o2.add_manager(u.user_name, false)
        u.reload
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['organizations'].length).to eq(2)
        expect(hash['organizations'][1]['id']).to eq(o2.global_id)
        expect(hash['organizations'][1]['type']).to eq('manager')
        expect(hash['organizations'][1]['full_manager']).to eq(false)
      end
      
      it "should include any supervision organziations" do
        o = Organization.create(:settings => {'total_licenses' => 2})
        o2 = Organization.create(:settings => {'total_licenses' => 2})
        u = User.create
        o.add_supervisor(u.user_name, true)
        u.reload
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['organizations'].length).to eq(1)
        expect(hash['organizations'][0]['id']).to eq(o.global_id)
        expect(hash['organizations'][0]['type']).to eq('supervisor')
        expect(hash['organizations'][0]['pending']).to eq(true)
        
        o2.add_supervisor(u.user_name, false)
        u.reload
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['organizations'].length).to eq(2)
        expect(hash['organizations'][1]['id']).to eq(o2.global_id)
        expect(hash['organizations'][1]['type']).to eq('supervisor')
        expect(hash['organizations'][1]['pending']).to eq(false)
      end
      
      it "should include a list of all organizations attached to the user" do
        o = Organization.create(:settings => {'total_licenses' => 2})
        o2 = Organization.create(:settings => {'total_licenses' => 2})
        o3 = Organization.create(:settings => {'total_licenses' => 2})
        u = User.create
        o.add_manager(u.user_name, true)
        u.reload
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['organizations'].length).to eq(1)
        expect(hash['organizations'][0]['id']).to eq(o.global_id)
        expect(hash['organizations'][0]['type']).to eq('manager')
        expect(hash['organizations'][0]['full_manager']).to eq(true)
        
        o2.add_supervisor(u.user_name, false)
        u.reload
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['organizations'].length).to eq(2)
        expect(hash['organizations'][1]['id']).to eq(o2.global_id)
        expect(hash['organizations'][1]['type']).to eq('supervisor')
        expect(hash['organizations'][1]['pending']).to eq(false)

        o3.add_user(u.user_name, false, true)
        u.reload
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['organizations'].length).to eq(3)
        expect(hash['organizations'][2]['id']).to eq(o3.global_id)
        expect(hash['organizations'][2]['type']).to eq('user')
        expect(hash['organizations'][2]['pending']).to eq(false)
        expect(hash['organizations'][2]['sponsored']).to eq(true)
      end
      
      it "should include a notification when a non-pending user is removed as a user from an organization" do
        o = Organization.create(:settings => {'total_licenses' => 2})
        o2 = Organization.create(:settings => {'total_licenses' => 2})
        u = User.create
        o.add_user(u.user_name, false)
        u.reload
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['organizations'].length).to eq(1)
        
        o.remove_user(u.user_name)
        Worker.process_queues
        u.reload
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['organizations'].length).to eq(0)
        expect(hash['notifications']).to_not eq(nil)
        expect(hash['notifications'].length).to eq(1)
        expect(hash['notifications'][0]['type']).to eq('org_removed')
        expect(hash['notifications'][0]['user_type']).to eq('user')
        expect(hash['notifications'][0]['org_id']).to eq(o.global_id)

        o2.add_user(u.user_name, true)
        o2.reload
        u.reload
        o2.remove_user(u.user_name)
        Worker.process_queues
        u.reload
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['organizations'].length).to eq(0)
        expect(hash['notifications'].length).to eq(1)
        expect(hash['notifications'][0]['org_id']).to eq(o.global_id)
      end
      
      it "should include a notification when a user is removed as a supervisor from an organization" do
        o = Organization.create(:settings => {'total_licenses' => 2})
        o2 = Organization.create(:settings => {'total_licenses' => 2})
        u = User.create
        o.add_supervisor(u.user_name, false)
        o2.add_supervisor(u.user_name, true)
        u.reload
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['organizations'].length).to eq(2)
        
        o.remove_supervisor(u.user_name)
        Worker.process_queues
        u.reload
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['organizations'].length).to eq(1)
        expect(hash['notifications']).to_not eq(nil)
        expect(hash['notifications'].length).to eq(1)
        expect(hash['notifications'][0]['type']).to eq('org_removed')
        expect(hash['notifications'][0]['user_type']).to eq('supervisor')
        expect(hash['notifications'][0]['org_id']).to eq(o.global_id)
        
        o2.remove_supervisor(u.user_name)
        Worker.process_queues
        u.reload
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['organizations'].length).to eq(0)
        expect(hash['notifications'].length).to eq(1)
        expect(hash['notifications'][0]['org_id']).to eq(o.global_id)
      end
    end
    
    it "should mark the subscription as limited_supervisor if appropriate" do
      u = User.create
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['subscription']['limited_supervisor']).to eq(nil)
      
      res = u.update_subscription({
        'subscribe' => true,
        'subscription_id' => '12345',
        'plan_id' => 'slp_monthly_free'
      })
      expect(res).to eq(true)

      u.reload
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['subscription']['free_premium']).to eq(true)
      expect(hash['subscription']['limited_supervisor']).to eq(false)
      
      User.where(:id => u).update_all(:created_at => 3.months.ago)
      u.reload
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['subscription']['free_premium']).to eq(true)
      expect(hash['subscription']['limited_supervisor']).to eq(true)
      
      o = Organization.create
      o.add_supervisor(u.user_name)
      
      u.reload
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['subscription']['free_premium']).to eq(true)
      expect(hash['subscription']['limited_supervisor']).to eq(false)
      
      o.remove_supervisor(u.user_name)
      u.reload
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['subscription']['free_premium']).to eq(true)
      expect(hash['subscription']['limited_supervisor']).to eq(true)
      
      u2 = User.create
      User.link_supervisor_to_user(u, u2)
      u.reload
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['subscription']['free_premium']).to eq(true)
      expect(hash['subscription']['limited_supervisor']).to eq(false)
      
      u2.expires_at = 1.week.ago
      u2.save
      u.reload
      hash = JsonApi::User.build_json(u, permissions: u)
      expect(hash['subscription']['free_premium']).to eq(true)
      expect(hash['subscription']['limited_supervisor']).to eq(true)
    end
    
    describe "feature_flags" do
      it "should return a feature_flags object" do
        u = User.create
        expect(FeatureFlags).to receive(:frontend_flags_for).with(u).and_return({'jump' => true})
        hash = JsonApi::User.build_json(u, permissions: u)
        expect(hash['feature_flags']).not_to eq(nil)
        expect(hash['feature_flags']['jump']).to eq(true)
        expect(hash['feature_flags']['slide']).to eq(nil)
      end
    end
  end
end
