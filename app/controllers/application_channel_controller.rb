class ApplicationChannelController < ApplicationController
  # Extending controllers has to define following constants:
  # PERMISSION = "admin.channel_xyz"
  # AREA = "XYZ::Account"

  prepend_before_action { authentication_check(permission: self.class::PERMISSION) }

  def index
    render json: channels_data
  end

  def create
    channel = Channel.create!(
      area:          self.class::AREA,
      options:       channel_options,
      active:        false,
      created_by_id: current_user.id,
      updated_by_id: current_user.id,
    )
    render json: channel
  end

  def update
    channel.update!(
      options:       channel_options,
      updated_by_id: current_user.id
    )
    render json: channel
  end

  def enable
    channel.update!(active: true)
    render json: channel
  end

  def disable
    channel.update!(active: false)
    render json: channel
  end

  def destroy
    channel.destroy!
    render json: {}
  end

  private

  def channel
    @channel ||= Channel.lookup(id: params[:id])
  end

  def channel_options
    params.permit(:adapter)
  end

  def channels_data
    channel_ids = []
    assets      = {}

    Channel.where(area: self.class::AREA).each do |channel|
      assets = channel.assets(assets)
      channel_ids.push(channel.id)
    end

    {
      assets:      assets,
      channel_ids: channel_ids
    }
  end
end
