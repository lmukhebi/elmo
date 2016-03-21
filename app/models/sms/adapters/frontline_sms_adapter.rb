class Sms::Adapters::FrontlineSmsAdapter < Sms::Adapters::Adapter

  def self.recognize_receive_request?(request)
    %w(from text frontline) - request.params.keys == []
  end

  def self.can_deliver?
    false
  end

  def reply_style
    :via_response
  end

  def deliver(message)
    raise NotImplementedError
  end

  def receive(request)
    params = request.params
    Sms::Incoming.new(
      from: params['from'],
      to: configatron.incoming_sms_number, # Assume it's this since IntelliSms doesn't provide it.
      body: params['text'],
      sent_at: Time.zone.now, # Frontline doesn't supply this
      adapter_name: service_name)
  end
end
