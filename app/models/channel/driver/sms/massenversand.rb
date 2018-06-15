class Channel::Driver::Sms::Massenversand
  NAME = 'sms/massenversand'.freeze
  FIELDS = %w[gateway token sender].freeze

  def initialize(options)
    @options = options
  end

  def send(recipient, message)
    Rails.logger.info "Sending SMS to recipient #{recipient}"

    return if Setting.import?

    Rails.logger.info "Backend sending Massenversand SMS to #{recipient}"
    begin
      url = build_url(recipient, message)

      if !Setting.developer?
        response = Faraday.get(url).body
        raise response if !response.match?('OK')
      end

      true
    rescue => e
      Rails.logger.debug "Massenversand error: #{e.inspect}"
      raise e
    end
  end

  private

  def build_url(recipient, message)
    params = {
      authToken: @options[:token],
      getID: 1,
      msg: message,
      msgtype: 'c',
      receiver: recipient,
      sender: @options[:sender]
    }

    @options[:gateway] + '?' + URI.encode_www_form(params)
  end
end
