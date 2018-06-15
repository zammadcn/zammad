class ChannelsSmsController < ApplicationChannelController
  PERMISSION = 'admin.channel_sms'.freeze
  AREA = 'Sms::Notification'.freeze

  def index
    render json: {
      data: channels_data,
      configuration: channels_configuration
    }
  end

  def test
    if params[:adapter].blank?
      render json: { error: "Missing parameter 'adapter'" }
      return
    end

    driver = Channel.driver_instance(params[:adapter])
    if driver.blank?
      render json: { error: "Unknown adapter #{params[:adapter]}" }
      return
    end

    instance = driver.new(channel_options)
    resp     = instance.send(test_options[:recipient], test_options[:message])

    render json: { success: resp }
  rescue => e
    render json: { error: e.inspect, error_human: e.message }
  end

  private

  def test_options
    params.permit(:recipient, :message)
  end

  def channel_options
    klass = Channel.driver_instance(params[:adapter])

    fields = klass.present? ? klass::FIELDS : []
    fields += [:adapter]

    params.permit(*fields)
  end

  def channels_configuration
    Dir
      .glob(Rails.root.join('app', 'models', 'channel', 'driver', 'sms', '*.rb'))
      .map { |path| File.basename(path) }
      .map { |filename| Channel.driver_instance("sms/#{filename}") }
      .compact
      .each_with_object({}) { |elem, memo| memo[elem::NAME] = single_channel_configuration(elem) }
  end

  def single_channel_configuration(klass)
    fields = klass::FIELDS.map do |elem|
      {
        identifier: elem,
        label: elem.humanize(keep_id_suffix: true)
      }
    end

    {
      fields: fields,
      name: klass::NAME.gsub('sms/', '').humanize
    }
  end
end
