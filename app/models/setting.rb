require 'mission_based'
require 'language_list'
class Setting < ActiveRecord::Base
  include MissionBased
  include LanguageList

  KEYS_TO_COPY = %w(timezone languages intellisms_username intellisms_password isms_hostname isms_username isms_password outgoing_sms_language)
  DEFAULTS = {:timezone => "UTC", :languages => "eng"}

  scope(:by_mission, lambda{|m| where(:mission_id => m ? m.id : nil)})
  scope(:default, where(DEFAULTS))
  
  before_validation(:cleanup_languages)
  before_validation(:ensure_english)
  validate(:lang_codes_are_valid)
  validate(:sms_adapter_is_valid)
  validate(:sms_credentials_are_valid)
  before_save(:save_sms_passwords)
  
  # accessors for password/password confirm fields
  attr_accessor :intellisms_password1, :intellisms_password2, :isms_password1, :isms_password2
  
  def self.table_exists?
    ActiveRecord::Base.connection.tables.include?("settings")
  end
  
  # gets called each time the current_mission is set by the application controller
  # checks if the settings have been copied to configatron since the *app* (not the request) was started
  def self.mission_was_set(mission)
    unless configatron.settings_copied?
      configatron.settings_copied = true
      copy_to_config(mission)
    end
  end
  
  # loads or creates a setting for the given mission
  def self.find_or_create(mission)
    return nil unless table_exists?
    setting = by_mission(mission).first || create_default(mission)
  end
  
  # copies all settings for the given mission to configatron
  def self.copy_to_config(mission)
    return if !table_exists?
    
    # get the setting or default
    find_or_create(mission).copy_to_config
  end
  
  # creates a default Setting by using the defaults specified in this file and those specified in the local config
  def self.create_default(mission)
    setting = by_mission(mission).default.new
    
    # copy default_settings from configatron
    configatron.default_settings.configatron_keys.each do |k| 
      setting.send("#{k}=", configatron.default_settings.send(k)) if setting.respond_to?("#{k}=")
    end
    
    setting.save!
    return setting
  end
  
  def copy_to_config
    # build hash
    hsh = Hash[*KEYS_TO_COPY.collect{|k| [k.to_sym, send(k)]}.flatten]
    
    # split languages into array
    hsh[:languages] = lang_codes
    
    # get class based on sms adapter setting; default to nil if setting is invalid
    hsh[:outgoing_sms_adapter] = begin
      Sms::Adapters::Factory.new.create(outgoing_sms_adapter)
    rescue ArgumentError
      nil
    end
    
    # copy to configatron
    configatron.configure_from_hash(hsh)
  end
  
  # converts a comma-delimited string of languages to an array of symbols
  def lang_codes
    (languages || "").split(",").collect{|c| c.to_sym}
  end
  
  # reverse of self.lang_codes
  def lang_codes=(codes)
    self.languages = codes.join(",")
  end
  
  private
    def ensure_english
      # make sure english exists and is at the front
      self.lang_codes = (lang_codes - [:eng]).insert(0, :eng)
      return true
    end
    
    def cleanup_languages
      self.lang_codes = lang_codes.collect{|c| c.to_s.downcase.gsub(/[^a-z]/, "").to_sym}
      return true
    end
    
    def lang_codes_are_valid
      lang_codes.each do |lc|
        errors.add(:languages, "code #{lc} is invalid") unless LANGS.keys.include?(lc)
      end
    end
    
    # sms adapter can be blank or must be valid according to the Factory
    def sms_adapter_is_valid
      errors.add(:outgoing_sms_adapter, "is invalid") unless outgoing_sms_adapter.blank? || Sms::Adapters::Factory.name_is_valid?(outgoing_sms_adapter)
    end
    
    # checks that the provided credentials are valid
    def sms_credentials_are_valid
      case outgoing_sms_adapter
      when "IntelliSms"
        errors.add(:intellisms_username, "can't be blank") if intellisms_username.blank?
        errors.add(:intellisms_password1, "did not match") unless intellisms_password1 == intellisms_password2
      when "Isms"
        errors.add(:isms_hostname, "can't be blank") if isms_hostname.blank?
        errors.add(:isms_username, "can't be blank") if isms_username.blank?
        errors.add(:isms_password1, "did not match") unless isms_password1 == isms_password2
      else
        # if there is no adapter then don't need to check anything
      end
    end
    
    # if the sms password temp fields are set (and they match, which is checked above), copy the value to the real field
    def save_sms_passwords
      unless outgoing_sms_adapter.blank?
        adapter = outgoing_sms_adapter.downcase
        input = send("#{adapter}_password1")
        send("#{adapter}_password=", input) unless input.blank?
      end
      return true
    end
end
