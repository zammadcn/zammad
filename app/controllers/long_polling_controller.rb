# Copyright (C) 2012-2016 Zammad Foundation, http://zammad-foundation.org/

class LongPollingController < ApplicationController
  skip_before_action :session_update # prevent race conditions

  # GET /api/v1/message_send
  def message_send
    new_connection = false

    # check client id
    client_id = client_id_verify
    if !client_id
      new_connection = true
      client_id = client_id_gen
      log 'new client connection', client_id
    end
    if !params['data']
      params['data'] = {}
    end
    session_data = {}
    if current_user && current_user.id
      session_data = { 'id' => current_user.id }
    end

    # spool messages for new connects
    if params['data']['spool']
      Sessions.spool_create(params['data'])
    end
    if params['data']['event'] == 'login'
      Sessions.create(client_id, session_data, { type: 'ajax' })
    elsif params['data']['event']
      message = Sessions::Event.run(
        event: params['data']['event'],
        payload: params['data'],
        session: session_data,
        client_id: client_id,
        clients: {},
        options: {},
      )
      if message
        Sessions.send(client_id, message)
      end
    else
      log "unknown message '#{params['data'].inspect}'", client_id
    end

    if new_connection
      result = { client_id: client_id }
      render json: result
    else
      render json: {}
    end
  end

  # GET /api/v1/message_receive
  def message_receive

    # check client id
    client_id = client_id_verify
    raise Exceptions::UnprocessableEntity, 'Invalid client_id receive!' if !client_id

    # check queue to send
    begin

      # update last ping
      4.times {
        sleep 0.25
      }
      #sleep 1
      Sessions.touch(client_id)

      # set max loop time to 24 sec. because of 30 sec. timeout of mod_proxy
      count = 3
      if Rails.env.production?
        count = 12
      end
      loop do
        count = count - 1
        queue = Sessions.queue(client_id)
        if queue && queue[0]
          logger.debug "send #{queue.inspect} to #{client_id}"
          render json: queue
          return
        end
        8.times {
          sleep 0.25
        }
        #sleep 2
        if count.zero?
          render json: { event: 'pong' }
          return
        end
      end
    rescue => e
      raise Exceptions::UnprocessableEntity, 'Invalid client_id in receive loop!'
    end
  end

  private

  def client_id_gen
    rand(9_999_999_999).to_s
  end

  def client_id_verify
    return if !params[:client_id]
    sessions = Sessions.sessions
    return if !sessions.include?(params[:client_id].to_s)
    params[:client_id].to_s
  end

  def log( data, client_id = '-' )
    logger.info "client(#{client_id}) #{data}"
  end
end
