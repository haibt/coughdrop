class Device < ActiveRecord::Base
  include GlobalId
  include SecureSerialize
  secure_serialize :settings
  belongs_to :user
  belongs_to :developer_key
  before_save :generate_defaults
  after_save :update_user_device_name

  def generate_defaults
    self.settings ||= {}
    self.settings['name'] ||= 'Web browser for Desktop' if self.default_device?
    self.settings['name'] ||= self.device_key.split(/\s/, 2)[1] if self.system_generated?
    true
  end
  
  def system_generated?
    self.developer_key_id == 0
  end
  
  def default_device?
    self.device_key == 'default' && self.system_generated?
  end
  
  def hidden?
    !!self.settings['hidden']
  end
  
  def last_used_at
    uses = (self.settings['keys'] || []).map{|k| k['last_timestamp'] }.sort
    time = uses.length > 0 && Time.at(uses.last) rescue nil
    time ||= self.created_at
  end
  
  def update_user_device_name
    # if the device_name changed the it'll need to be updated on the user record
  end
  
  def generate_token!(force_long_token=false)
    raise "device must already be saved" unless self.id
    clean_old_keys
    # TODO: this check should probably be based on developer key whenever we do that part
    if !self.system_generated?
      # browsers are different than devices in that they can have multiple tokens for the same device
      self.settings['keys'] = []
    end
    key = "#{self.global_id}~#{Digest::SHA512.hexdigest(Time.now.to_i.to_s + rand(99999).to_s + self.global_id)}"
    
    # Keep track of which devices were used most recently/frequently to help
    # display most-relevant ones in the UI under "user devices".
    self.settings['token_history'] ||= []
    self.settings['token_history'] << Time.now.to_i
    self.settings['keys'] << {
      'value' => key,
      'timestamp' => Time.now.to_i,
      'last_timestamp' => Time.now.to_i,
      'timeout' => self.inactivity_timeout(force_long_token)
    }
    self.save
  end
  
  def logout!
    self.settings['keys'] = []
    self.save
  end
  
  def unique_device_key
    raise "must be saved first" unless self.global_id
    return device_key if self.system_generated?
    raise "missing developer_key_id" unless self.developer_key_id
    "#{self.device_key}_#{self.developer_key_id}"
  end
  
  def inactivity_timeout(force_long_timeout=false)
    (self.default_device? && !force_long_timeout) ? 6.hours.to_i : 14.days.to_i
  end
  
  def clean_old_keys
    self.settings ||= {}
    keys = self.settings['keys'] || []
    keys = keys.select{|k| k['last_timestamp'] > Time.now.to_i - (k['timeout'] || self.inactivity_timeout) }
    self.settings['keys'] = keys
  end
  
  def valid_token?(token)
    clean_old_keys
    keys = (self.settings && self.settings['keys']) || []
    key = keys.detect{|k| k['value'] == token }
    if key && key['last_timestamp'] < 30.minutes.ago.to_i
      key['last_timestamp'] = Time.now.to_i
      self.settings['keys'].each_with_index do |key, idx|
        if key['token'] == token
          self.settings['keys'][idx] = key
        end
      end
      self.save
    end
    !!key
  end
  
  def token
    clean_old_keys
    if self.settings['keys'].empty?
      self.generate_token!
    end
    self.settings['keys'][-1]['value']
  end
end
