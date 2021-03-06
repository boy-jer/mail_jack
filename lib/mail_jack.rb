require 'mail_jack/config'
require 'mail_jack/mailer'
require 'mail_jack/interceptor'
require 'mail_jack/params_decoder'
require 'mail_jack/railtie'
##################################################################################
#
#  module MailJack
#
#     - like LoJack...get it?
# 
#  This module will append query parameters of your choosing to every link
#  in the mailers you specify so that you can track click throughs.  The parameters
#  are dynamically evaluated at mail send time with the Proc of your choosing.  Cool, huh.  
#
#  Usage:
# 
#     # config/initializers/mail_tracker.rb
#     MailJack.config do |config|
# 
#       # specify what mailer classes you want to add tracking to
#       config.mailers = [:user_notifier]
#
#       # specify the regex that should be used filter hrefs
#       # (this is useful so you don't add tracking params to 3rd party urls off your site)
#       config.href_filter = /myapplication.com/
#
#       # MOST IMPORTANT PART
#       # Specify what attributes you want to track and the Proc that figures them out
#       # The attributes can be any name.  The value must be an object that responds to #call
#       config.trackable do |track|
#         track.campaign = lambda{|mailer| mailer.action_name}
#         track.campaign_group = lambda{|mailer| mailer.class.name}
#         track.foobarbizbat = lambda{|mailer| Time.now}
#       end
#     end
#
#  Under the Covers
#
#     1. You specify what mailer classes you want to track, and any other options
#     2. You specify the attributes that will be tracked the Proc that should be used to figure out the value
#     3. Mail::Message class has the trackable keys added as attr_accessors
#     4. ActionMailer::Base#mail method is decorated via alias_method_chain for each mailer class specified 
#     5. MailJack registers a Mail::Interceptor to intercept all outgoing mail
#     5. When ActionMailer::Base#mail is called, the undecorated method is called first, then MailJack
#         fetches the values of the attributes specified by calling the Proc specified and passing in the mailer
#         instance, so You can figure out what value should be returned
#     6. Those values are then assigned to the Mail::Message class via the accessors we added in step 3
#     7. The mail is sent and is subsequently intercepted by MailJack::Interceptor which then reads the
#         the values passed along into the Mail::Message, creates a query string, and finds all relevant href's
#         and appends the tracking parameters
#  
##################################################################################
module MailJack  
  def self.config

    # return configuration if already configured
    return @@config if defined?(@@config) and @@config.kind_of?(Config)
    
    raise ArgumentError, "you must configure MailJack to use it.  call MailJack.config{|config| ...} from an initializer" unless block_given?

    # yield configuration
    @@config = Config.new
    yield @@config

    # dynamically define the accessors onto Mail::Message
    # so we can assign them later in the Interceptor
    Mail::Message.class_eval do
      attr_accessor *@@config.trackables.keys if @@config.trackables
    end

    # include the module that decorates(ie monkey patches)
    # the Mail::Message#mail method
    @@config.mailers.each do |mailer|
      mailer.to_s.classify.constantize.send(:include, Mailer)
    end

    # register the interceptor
    Mail.register_interceptor(MailJack::Interceptor)

    @@config.configured = true
  end

  def self.configured?
    defined?(@@config) and @@config.configured?
  end
  
  # Fetch attributes gets the dynamically defined attributes
  # off the object passed in, the object is ActionMailer::Base instance
  def self.fetch_attributes(mailer)
    map = {}
    self.trackables.each do |attribute, proc|
      map[attribute] = proc.call(mailer)
    end
    return map
  end

  def self.trackables
    @@config.trackables
  end  
end