class Channel::Driver::Sms::Twilio
  NAME = 'sms/twilio'.freeze
  FIELDS = %w[account_id token sender].freeze

  def initialize(options)
    @options = options
  end

  def send(recipient, message)
    Rails.logger.info "Sending SMS to recipient #{recipient}"

    return if Setting.import?

    Rails.logger.info "Backend sending Twilio SMS to #{recipient}"
    begin
      if !Setting.developer?
        result = api.messages.create(
          from: @options[:sender],
          to: recipient,
          body: message
        )

        raise result.error_message if result.error_code.positive?
      end

      true
    rescue => e
      Rails.logger.debug "Twilio error: #{e.inspect}"
      raise e
    end
  end

  private

  def api
    @api ||= ::Twilio::REST::Client.new @options[:account_id], @options[:token]
  end
end
