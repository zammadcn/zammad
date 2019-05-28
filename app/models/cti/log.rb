module Cti
  class Log < ApplicationModel
    include HasSearchIndexBackend

    self.table_name = 'cti_logs'

    store :preferences

    validates :state, format: { with: /\A(newCall|answer|hangup)\z/,  message: 'newCall|answer|hangup is allowed' }

    after_commit :push_incoming_call, :push_caller_list_update

=begin

  Cti::Log.create!(
    direction: 'in',
    from: '007',
    from_comment: '',
    to: '008',
    to_comment: 'BBB',
    call_id: '1',
    comment: '',
    state: 'newCall',
    done: true,
  )

  Cti::Log.create!(
    direction: 'in',
    from: '007',
    from_comment: '',
    to: '008',
    to_comment: '',
    call_id: '2',
    comment: '',
    state: 'answer',
    done: true,
  )

  Cti::Log.create!(
    direction: 'in',
    from: '009',
    from_comment: '',
    to: '010',
    to_comment: '',
    call_id: '3',
    comment: '',
    state: 'hangup',
    done: true,
  )

example data, can be used for demo

  Cti::Log.create!(
    direction: 'in',
    from: '4930609854180',
    from_comment: 'Franz Bauer',
    to: '4930609811111',
    to_comment: 'Bob Smith',
    call_id: '435452113',
    comment: '',
    state: 'newCall',
    done: false,
    preferences: {
      from: [
        {
          caller_id: '4930726128135',
          comment: nil,
          level: 'known',
          object: 'User',
          o_id: 2,
          user_id: 2,
        },
        {
          caller_id: '4930726128135',
          comment: nil,
          level: 'maybe',
          object: 'User',
          o_id: 2,
          user_id: 3,
        },
      ]
    },
    created_at: Time.zone.now,
  )

  Cti::Log.create!(
    direction: 'out',
    from: '4930609854180',
    from_comment: 'Franz Bauer',
    to: '4930609811111',
    to_comment: 'Bob Smith',
    call_id: rand(999_999_999),
    comment: '',
    state: 'newCall',
    done: true,
    preferences: {
      to: [
        {
          caller_id: '4930726128135',
          comment: nil,
          level: 'known',
          object: 'User',
          o_id: 2,
          user_id: 2,
        }
      ]
    },
    created_at: Time.zone.now - 20.seconds,
  )

  Cti::Log.create!(
    direction: 'in',
    from: '4930609854180',
    from_comment: 'Franz Bauer',
    to: '4930609811111',
    to_comment: 'Bob Smith',
    call_id: rand(999_999_999),
    comment: '',
    state: 'answer',
    done: true,
    preferences: {
      from: [
        {
          caller_id: '4930726128135',
          comment: nil,
          level: 'known',
          object: 'User',
          o_id: 2,
          user_id: 2,
        }
      ]
    },
    initialized_at: Time.zone.now - 20.seconds,
    start_at: Time.zone.now - 30.seconds,
    duration_waiting_time: 20,
    created_at: Time.zone.now - 20.seconds,
  )

  Cti::Log.create!(
    direction: 'in',
    from: '4930609854180',
    from_comment: 'Franz Bauer',
    to: '4930609811111',
    to_comment: 'Bob Smith',
    call_id: rand(999_999_999),
    comment: '',
    state: 'hangup',
    comment: 'normalClearing',
    done: false,
    preferences: {
      from: [
        {
          caller_id: '4930726128135',
          comment: nil,
          level: 'known',
          object: 'User',
          o_id: 2,
          user_id: 2,
        }
      ]
    },
    initialized_at: Time.zone.now - 80.seconds,
    start_at: Time.zone.now - 45.seconds,
    end_at: Time.zone.now,
    duration_waiting_time: 35,
    duration_talking_time: 45,
    created_at: Time.zone.now - 80.seconds,
  )

  Cti::Log.create!(
    direction: 'in',
    from: '4930609854180',
    from_comment: 'Franz Bauer',
    to: '4930609811111',
    to_comment: 'Bob Smith',
    call_id: rand(999_999_999),
    comment: '',
    state: 'hangup',
    done: true,
    start_at: Time.zone.now - 15.seconds,
    end_at: Time.zone.now,
    preferences: {
      from: [
        {
          caller_id: '4930726128135',
          comment: nil,
          level: 'known',
          object: 'User',
          o_id: 2,
          user_id: 2,
        }
      ]
    },
    initialized_at: Time.zone.now - 5.minutes,
    start_at: Time.zone.now - 3.minutes,
    end_at: Time.zone.now - 20.seconds,
    duration_waiting_time: 120,
    duration_talking_time: 160,
    created_at: Time.zone.now - 5.minutes,
  )

  Cti::Log.create!(
    direction: 'in',
    from: '4930609854180',
    from_comment: 'Franz Bauer',
    to: '4930609811111',
    to_comment: '',
    call_id: rand(999_999_999),
    comment: '',
    state: 'hangup',
    done: true,
    start_at: Time.zone.now - 15.seconds,
    end_at: Time.zone.now,
    preferences: {
      from: [
        {
          caller_id: '4930726128135',
          comment: nil,
          level: 'known',
          object: 'User',
          o_id: 2,
          user_id: 2,
        }
      ]
    },
    initialized_at: Time.zone.now - 60.minutes,
    start_at: Time.zone.now - 59.minutes,
    end_at: Time.zone.now - 2.minutes,
    duration_waiting_time: 60,
    duration_talking_time: 3420,
    created_at: Time.zone.now - 60.minutes,
  )

  Cti::Log.create!(
    direction: 'in',
    from: '4930609854180',
    from_comment: 'Franz Bauer',
    to: '4930609811111',
    to_comment: 'Bob Smith',
    call_id: rand(999_999_999),
    comment: '',
    state: 'hangup',
    done: true,
    start_at: Time.zone.now - 15.seconds,
    end_at: Time.zone.now,
    preferences: {
      from: [
        {
          caller_id: '4930726128135',
          comment: nil,
          level: 'maybe',
          object: 'User',
          o_id: 2,
          user_id: 2,
        }
      ]
    },
    initialized_at: Time.zone.now - 240.minutes,
    start_at: Time.zone.now - 235.minutes,
    end_at: Time.zone.now - 222.minutes,
    duration_waiting_time: 300,
    duration_talking_time: 1080,
    created_at: Time.zone.now - 240.minutes,
  )

  Cti::Log.create!(
    direction: 'in',
    from: '4930609854180',
    to: '4930609811112',
    call_id: rand(999_999_999),
    comment: '',
    state: 'hangup',
    done: true,
    start_at: Time.zone.now - 20.seconds,
    end_at: Time.zone.now,
    preferences: {},
    initialized_at: Time.zone.now - 1440.minutes,
    start_at: Time.zone.now - 1430.minutes,
    end_at: Time.zone.now - 1429.minutes,
    duration_waiting_time: 600,
    duration_talking_time: 660,
    created_at: Time.zone.now - 1440.minutes,
  )

=end

=begin

  Cti::Log.log(current_user)

returns

  {
    list: [log_record1, log_record2, log_record3],
    assets: {...},
  }

=end

    def self.log(current_user)
      list = Cti::Log.log_records(current_user)

      # add assets
      assets = list.map(&:preferences)
                   .map { |p| p.slice(:from, :to) }
                   .map(&:values).flatten
                   .map { |caller_id| caller_id[:user_id] }.compact
                   .map { |user_id| User.lookup(id: user_id) }.compact
                   .each.with_object({}) { |user, a| user.assets(a) }

      {
        list:   list,
        assets: assets,
      }
    end

=begin

  Cti::Log.log_records(current_user)

returns

  [log_record1, log_record2, log_record3]

=end

    def self.log_records(current_user)
      cti_config = Setting.get('cti_config')
      if cti_config[:notify_map].present?
        return Cti::Log.where(queue: queues_of_user(current_user, cti_config[:notify_map])).order(created_at: :desc).limit(60)
      end

      Cti::Log.order(created_at: :desc).limit(60)
    end

=begin

processes a incoming event

Cti::Log.process(
  cause: '',
  event: 'newCall',
  user: 'user 1',
  from: '4912347114711',
  to: '4930600000000',
  callId: '43545211', # or call_id
  direction: 'in',
  queue: 'helpdesk', # optional
)

=end

    def self.process(params)
      cause   = params['cause']
      event   = params['event']
      user    = params['user']
      queue   = params['queue']
      call_id = params['callId'] || params['call_id']
      if user.class == Array
        user = user.join(', ')
      end

      from_comment = nil
      to_comment = nil
      preferences = nil
      done = true
      if params['direction'] == 'in'
        if user.present?
          to_comment = user
        elsif queue.present?
          to_comment = queue
        end
        from_comment, preferences = CallerId.get_comment_preferences(params['from'], 'from')
        if queue.blank?
          queue = params['to']
        end
      else
        from_comment = user
        to_comment, preferences = CallerId.get_comment_preferences(params['to'], 'to')
        if queue.blank?
          queue = params['from']
        end
      end

      log = find_by(call_id: call_id)

      case event
      when 'newCall'
        if params['direction'] == 'in'
          done = false
        end
        raise "call_id #{call_id} already exists!" if log

        create(
          direction:      params['direction'],
          from:           params['from'],
          from_comment:   from_comment,
          to:             params['to'],
          to_comment:     to_comment,
          call_id:        call_id,
          comment:        cause,
          queue:          queue,
          state:          event,
          initialized_at: Time.zone.now,
          preferences:    preferences,
          done:           done,
        )
      when 'answer'
        raise "No such call_id #{call_id}" if !log
        return if log.state == 'hangup' # call is already hangup, ignore answer

        log.with_lock do
          log.state = 'answer'
          log.start_at = Time.zone.now
          log.duration_waiting_time = log.start_at.to_i - log.initialized_at.to_i
          if user
            log.to_comment = user
          end
          log.done = true
          log.comment = cause
          log.save
        end

        log.push_open_ticket_screen(params, log)
      when 'hangup'
        raise "No such call_id #{call_id}" if !log

        log.with_lock do
          log.done = done
          if params['direction'] == 'in'
            if log.state == 'newCall' && cause != 'forwarded'
              log.done = false
            elsif log.to_comment == 'voicemail'
              log.done = false
            end
          end
          log.state = 'hangup'
          log.end_at = Time.zone.now
          if log.start_at
            log.duration_talking_time = log.end_at.to_i - log.start_at.to_i
          elsif !log.duration_waiting_time && log.initialized_at
            log.duration_waiting_time = log.end_at.to_i - log.initialized_at.to_i
          end
          log.comment = cause
          log.save
        end
      else
        raise ArgumentError, "Unknown event #{event.inspect}"
      end
    end

    def push_open_ticket_screen_recipient(params, _log)

      # try to find answering which answered call
      user = nil

      # based on answeringNumber
      if params[:answeringNumber].present?
        user = user_ids_by_number(params[:answeringNumber]).first
      end

      # based on user param
      if !user && params[:user].present?
        user = User.find_by(login: params[:user].downcase)
      end

      # based on user_id param
      if !user && params[:user_id].present?
        user = User.find_by(id: params[:user_id])
      end

      user
    end

    def push_open_ticket_screen(params, log)
      return true if params[:event] != 'answer'
      return true if params[:direction] != 'in'

      user = push_open_ticket_screen_recipient(params, log)
      return if !user

      id = rand(999_999_999)
      Sessions.send_to(user.id, {
                         event: 'remote_task',
                         data:  {
                           key:        "TicketCreateScreen-#{id}",
                           controller: 'TicketCreate',
                           params:     { customer_id: user.id.to_s, title: 'Call', id: id },
                           show:       true,
                           url:        "ticket/create/id/#{id}"
                         },
                       })
    end

    def push_incoming_call
      return true if destroyed?
      return true if state != 'newCall'
      return true if direction != 'in'

      # check if only a certain user should get the notification
      config = Setting.get('cti_config')
      if config && config[:notify_map].present?
        user_ids = []
        config[:notify_map].each do |row|
          next if row[:user_ids].blank? || row[:queue] != to

          row[:user_ids].each do |user_id|
            user = User.find_by(id: user_id)
            next if !user
            next if !user.permissions?('cti.agent')

            user_ids.push user.id
          end
        end

        # add agents which have this number directly assigned
        user_ids_by_number(to).each do |user|
          user_ids.push user.id
        end

        user_ids.uniq.each do |user_id|
          Sessions.send_to(
            user_id,
            {
              event: 'cti_event',
              data:  self,
            },
          )
        end
        return true
      end

      # send notify about event
      users = User.with_permissions('cti.agent')
      users.each do |user|
        Sessions.send_to(
          user.id,
          {
            event: 'cti_event',
            data:  self,
          },
        )
      end
      true
    end

    def self.push_caller_list_update?(record)
      list_ids = Cti::Log.order(created_at: :desc).limit(60).pluck(:id)
      return true if list_ids.include?(record.id)

      false
    end

    def push_caller_list_update
      return false if !Cti::Log.push_caller_list_update?(self)

      # send notify on create/update/delete
      users = User.with_permissions('cti.agent')
      users.each do |user|
        Sessions.send_to(
          user.id,
          {
            event: 'cti_list_push',
          },
        )
      end
      true
    end

=begin

cleanup caller logs

  Cti::Log.cleanup

optional you can put the max oldest chat entries as argument

  Cti::Log.cleanup(12.months)

=end

    def self.cleanup(diff = 12.months)
      Cti::Log.where('created_at < ?', Time.zone.now - diff).delete_all
      true
    end

    # adds virtual attributes when rendering #to_json
    # see http://api.rubyonrails.org/classes/ActiveModel/Serialization.html
    def attributes
      virtual_attributes = {
        'from_pretty' => from_pretty,
        'to_pretty'   => to_pretty,
      }

      super.merge(virtual_attributes)
    end

    def from_pretty
      parsed = TelephoneNumber.parse(from&.sub(/^\+?/, '+'))
      parsed.send(parsed.valid? ? :international_number : :original_number)
    end

    def to_pretty
      parsed = TelephoneNumber.parse(to&.sub(/^\+?/, '+'))
      parsed.send(parsed.valid? ? :international_number : :original_number)
    end

    def self.queues_of_user(user, config)
      queues = []
      config.each do |row|
        next if row[:user_ids].blank?
        next if !row[:user_ids].include?(user.id.to_s) && !row[:user_ids].include?(user.id)

        queues.push row[:queue]
      end
      if user.phone.present?
        caller_ids = Cti::CallerId.extract_numbers(user.phone)
        queues = queues.concat(caller_ids)
      end
      queues
    end

    def user_ids_by_number(number)
      users = []
      caller_ids = Cti::CallerId.extract_numbers(number)
      caller_id_records = Cti::CallerId.lookup(caller_ids)
      caller_id_records.each do |caller_id_record|
        next if caller_id_record.object != 'User'
        next if caller_id_record.level != 'known'

        user = User.find_by(id: caller_id_record.o_id)
        next if !user
        next if !user.permissions?('cti.agent')

        users.push user
      end
      users
    end
  end
end
