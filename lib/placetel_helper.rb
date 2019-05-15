class PlacetelHelper

  def self.config_integration
    Setting.get('placetel_config')
  end

  def self.get_user_id_by_peer(peer)
    return if config_integration.blank? || config_integration[:user_device_map].blank?

    config_integration[:user_device_map].each do |row|
      next if row[:user_id].blank?
      return row[:user_id] if row[:device_id] == peer
    end
    nil
  end

  def get_voip_user_by_peer(peer)
    load_voip_users[peer]
  end

  def load_voip_users
    return {} if config_integration.blank? || config_integration[:api_token].blank?

    list = Cache.get('placetelGetVoipUsers')
    return list if list

    response = UserAgent.post(
      'https://api.placetel.de/api/getVoIPUsers.json',
      {
        api_key: config_integration[:api_token],
      },
      {
        log:           {
          facility: 'placetel',
        },
        json:          true,
        open_timeout:  4,
        read_timeout:  6,
        total_timeout: 6,
      },
    )
    if !response.success?
      logger.error "Can't fetch getVoipUsers from '#{url}', http code: #{response.code}"
      Cache.write('placetelGetVoipUsers', {}, { expires_in: 1.hour })
      return {}
    end
    result = response.data
    if result.blank?
      logger.error "Can't fetch getVoipUsers from '#{url}', result: #{response.inspect}"
      Cache.write('placetelGetVoipUsers', {}, { expires_in: 1.hour })
      return {}
    end
    if result.is_a?(Hash) && (result['result'] == '-1' || result['result_code'] == 'error')
      logger.error "Can't fetch getVoipUsers from '#{url}', result: #{result.inspect}"
      Cache.write('placetelGetVoipUsers', {}, { expires_in: 1.hour })
      return {}
    end
    if !result.is_a?(Array)
      logger.error "Can't fetch getVoipUsers from '#{url}', result: #{result.inspect}"
      Cache.write('placetelGetVoipUsers', {}, { expires_in: 1.hour })
      return {}
    end

    list = {}
    result.each do |entry|
      next if entry['name'].blank?

      if entry['uid'].present?
        list[entry['uid']] = entry['name']
      end
      next if entry['uid2'].blank?

      list[entry['uid2']] = entry['name']
    end
    Cache.write('placetelGetVoipUsers', list, { expires_in: 24.hours })
    list
  end

end
