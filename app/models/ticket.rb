# Copyright (C) 2012-2016 Zammad Foundation, http://zammad-foundation.org/

class Ticket < ApplicationModel
  include HasActivityStreamLog
  include ChecksClientNotification
  include ChecksLatestChangeObserved
  include HasHistory
  include HasTags
  include HasSearchIndexBackend
  include HasOnlineNotifications
  include HasKarmaActivityLog
  include HasLinks
  include Ticket::ChecksAccess

  include Ticket::Escalation
  include Ticket::Subject
  load 'ticket/assets.rb'
  include Ticket::Assets
  load 'ticket/search_index.rb'
  include Ticket::SearchIndex
  extend Ticket::Search

  store          :preferences
  before_create  :check_generate, :check_defaults, :check_title, :set_default_state, :set_default_priority
  after_create   :check_escalation_update
  before_update  :check_defaults, :check_title, :reset_pending_time
  after_update   :check_escalation_update

  validates :group_id, presence: true

  activity_stream_permission 'ticket.agent'

  activity_stream_attributes_ignored :organization_id, # organization_id will channge automatically on user update
                                     :create_article_type_id,
                                     :create_article_sender_id,
                                     :article_count,
                                     :first_response_at,
                                     :first_response_escalation_at,
                                     :first_response_in_min,
                                     :first_response_diff_in_min,
                                     :close_at,
                                     :close_escalation_at,
                                     :close_in_min,
                                     :close_diff_in_min,
                                     :update_escalation_at,
                                     :update_in_min,
                                     :update_diff_in_min,
                                     :last_contact_at,
                                     :last_contact_agent_at,
                                     :last_contact_customer_at,
                                     :last_owner_update_at,
                                     :preferences

  history_attributes_ignored :create_article_type_id,
                             :create_article_sender_id,
                             :article_count,
                             :preferences

  belongs_to    :group,                  class_name: 'Group'
  has_many      :articles,               class_name: 'Ticket::Article', after_add: :cache_update, after_remove: :cache_update, dependent: :destroy
  has_many      :ticket_time_accounting, class_name: 'Ticket::TimeAccounting', dependent: :destroy
  belongs_to    :organization,           class_name: 'Organization'
  belongs_to    :state,                  class_name: 'Ticket::State'
  belongs_to    :priority,               class_name: 'Ticket::Priority'
  belongs_to    :owner,                  class_name: 'User'
  belongs_to    :customer,               class_name: 'User'
  belongs_to    :created_by,             class_name: 'User'
  belongs_to    :updated_by,             class_name: 'User'
  belongs_to    :create_article_type,    class_name: 'Ticket::Article::Type'
  belongs_to    :create_article_sender,  class_name: 'Ticket::Article::Sender'

  self.inheritance_column = nil

  attr_accessor :callback_loop

=begin

get user access conditions

  conditions = Ticket.access_condition( User.find(1) , 'full')

returns

  result = [user1, user2, ...]

=end

  def self.access_condition(user, access)
    if user.permissions?('ticket.agent')
      ['group_id IN (?)', user.group_ids_access(access)]
    elsif !user.organization || ( !user.organization.shared || user.organization.shared == false )
      ['tickets.customer_id = ?', user.id]
    else
      ['(tickets.customer_id = ? OR tickets.organization_id = ?)', user.id, user.organization.id]
    end
  end

=begin

processes tickets which have reached their pending time and sets next state_id

  processed_tickets = Ticket.process_pending

returns

  processed_tickets = [<Ticket>, ...]

=end

  def self.process_pending
    result = []

    # process pending action tickets
    pending_action = Ticket::StateType.find_by(name: 'pending action')
    ticket_states_pending_action = Ticket::State.where(state_type_id: pending_action)
                                                .where.not(next_state_id: nil)
    if ticket_states_pending_action.present?
      next_state_map = {}
      ticket_states_pending_action.each { |state|
        next_state_map[state.id] = state.next_state_id
      }

      tickets = where(state_id: next_state_map.keys)
                .where('pending_time <= ?', Time.zone.now)

      tickets.each { |ticket|
        Transaction.execute do
          ticket.state_id      = next_state_map[ticket.state_id]
          ticket.updated_at    = Time.zone.now
          ticket.updated_by_id = 1
          ticket.save!
        end
        result.push ticket
      }
    end

    # process pending reminder tickets
    pending_reminder = Ticket::StateType.find_by(name: 'pending reminder')
    ticket_states_pending_reminder = Ticket::State.where(state_type_id: pending_reminder)

    if ticket_states_pending_reminder.present?
      reminder_state_map = {}
      ticket_states_pending_reminder.each { |state|
        reminder_state_map[state.id] = state.next_state_id
      }

      tickets = where(state_id: reminder_state_map.keys)
                .where('pending_time <= ?', Time.zone.now)

      tickets.each { |ticket|

        article_id = nil
        article = Ticket::Article.last_customer_agent_article(ticket.id)
        if article
          article_id = article.id
        end

        # send notification
        Transaction::BackgroundJob.run(
          object: 'Ticket',
          type: 'reminder_reached',
          object_id: ticket.id,
          article_id: article_id,
          user_id: 1,
        )

        result.push ticket
      }
    end

    result
  end

=begin

processes escalated tickets

  processed_tickets = Ticket.process_escalation

returns

  processed_tickets = [<Ticket>, ...]

=end

  def self.process_escalation
    result = []

    # get max warning diff

    tickets = where('escalation_at <= ?', Time.zone.now + 15.minutes)

    tickets.each { |ticket|

      # get sla
      sla = ticket.escalation_calculation_get_sla

      article_id = nil
      article = Ticket::Article.last_customer_agent_article(ticket.id)
      if article
        article_id = article.id
      end

      # send escalation
      if ticket.escalation_at < Time.zone.now
        Transaction::BackgroundJob.run(
          object: 'Ticket',
          type: 'escalation',
          object_id: ticket.id,
          article_id: article_id,
          user_id: 1,
        )
        result.push ticket
        next
      end

      # check if warning need to be sent
      Transaction::BackgroundJob.run(
        object: 'Ticket',
        type: 'escalation_warning',
        object_id: ticket.id,
        article_id: article_id,
        user_id: 1,
      )
      result.push ticket
    }
    result
  end

=begin

processes tickets which auto unassign time has reached

  processed_tickets = Ticket.process_auto_unassign

returns

  processed_tickets = [<Ticket>, ...]

=end

  def self.process_auto_unassign

    # process pending action tickets
    state_ids = Ticket::State.by_category(:work_on).pluck(:id)
    return [] if state_ids.blank?
    result = []
    groups = Group.where(active: true).where('assignment_timeout IS NOT NULL AND groups.assignment_timeout != 0')
    return [] if groups.blank?
    groups.each { |group|
      next if group.assignment_timeout.blank?
      ticket_ids = Ticket.where('state_id IN (?) AND owner_id != 1 AND group_id = ?', state_ids, group.id).limit(600).pluck(:id)
      ticket_ids.each { |ticket_id|
        ticket = Ticket.find_by(id: ticket_id)
        next if !ticket
        minutes_since_last_assignment = Time.zone.now - ticket.last_owner_update_at
        next if (minutes_since_last_assignment / 60) <= group.assignment_timeout
        Transaction.execute do
          ticket.owner_id      = 1
          ticket.updated_at    = Time.zone.now
          ticket.updated_by_id = 1
          ticket.save!
        end
        result.push ticket
      }
    }

    result
  end

=begin

merge tickets

  ticket = Ticket.find(123)
  result = ticket.merge_to(
    ticket_id: 123,
    user_id:   123,
  )

returns

  result = true|false

=end

  def merge_to(data)

    # prevent cross merging tickets
    target_ticket = Ticket.find_by(id: data[:ticket_id])
    raise 'no target ticket given' if !target_ticket
    raise Exceptions::UnprocessableEntity, 'ticket already merged, no merge into merged ticket possible' if target_ticket.state.state_type.name == 'merged'

    # check different ticket ids
    raise Exceptions::UnprocessableEntity, 'Can\'t merge ticket with it self!' if id == target_ticket.id

    # update articles
    Transaction.execute do

      Ticket::Article.where(ticket_id: id).each(&:touch)

      # quiet update of reassign of articles
      Ticket::Article.where(ticket_id: id).update_all(['ticket_id = ?', data[:ticket_id]])

      # update history

      # create new merge article
      Ticket::Article.create(
        ticket_id: id,
        type_id: Ticket::Article::Type.lookup(name: 'note').id,
        sender_id: Ticket::Article::Sender.lookup(name: 'Agent').id,
        body: 'merged',
        internal: false,
        created_by_id: data[:user_id],
        updated_by_id: data[:user_id],
      )

      # add history to both

      # reassign links to the new ticket
      Link.where(
        link_object_source_id: Link::Object.find_by(name: 'Ticket').id,
        link_object_source_value: id,
      ).update_all(link_object_source_value: data[:ticket_id])
      Link.where(
        link_object_target_id: Link::Object.find_by(name: 'Ticket').id,
        link_object_target_value: id,
      ).update_all(link_object_target_value: data[:ticket_id])

      # link tickets
      Link.add(
        link_type: 'parent',
        link_object_source: 'Ticket',
        link_object_source_value: data[:ticket_id],
        link_object_target: 'Ticket',
        link_object_target_value: id
      )

      # set state to 'merged'
      self.state_id = Ticket::State.lookup(name: 'merged').id

      # rest owner
      self.owner_id = 1

      # save ticket
      save!

      # touch new ticket (to broadcast change)
      target_ticket.touch
    end
    true
  end

=begin

check if online notifcation should be shown in general as already seen with current state

  ticket = Ticket.find(1)
  seen = ticket.online_notification_seen_state(user_id_check)

returns

  result = true # or false

check if online notifcation should be shown for this user as already seen with current state

  ticket = Ticket.find(1)
  seen = ticket.online_notification_seen_state(check_user_id)

returns

  result = true # or false

=end

  def online_notification_seen_state(user_id_check = nil)
    state      = Ticket::State.lookup(id: state_id)
    state_type = Ticket::StateType.lookup(id: state.state_type_id)

    # always to set unseen for ticket owner and users which did not the update
    if state_type.name != 'merged'
      if user_id_check
        return false if user_id_check == owner_id && user_id_check != updated_by_id
      end
    end

    # set all to seen if pending action state is a closed or merged state
    if state_type.name == 'pending action' && state.next_state_id
      state      = Ticket::State.lookup(id: state.next_state_id)
      state_type = Ticket::StateType.lookup(id: state.state_type_id)
    end

    # set all to seen if new state is pending reminder state
    if state_type.name == 'pending reminder'
      if user_id_check
        return false if owner_id == 1
        return false if updated_by_id != owner_id && user_id_check == owner_id
        return true
      end
      return true
    end

    # set all to seen if new state is a closed or merged state
    return true if state_type.name == 'closed'
    return true if state_type.name == 'merged'
    false
  end

=begin

get count of tickets and tickets which match on selector

  ticket_count, tickets = Ticket.selectors(params[:condition], limit, current_user, 'full')

=end

  def self.selectors(selectors, limit = 10, current_user = nil, access = 'full')
    raise 'no selectors given' if !selectors
    query, bind_params, tables = selector2sql(selectors, current_user)
    return [] if !query

    ActiveRecord::Base.transaction(requires_new: true) do
      begin
        if !current_user
          ticket_count = Ticket.where(query, *bind_params).joins(tables).count
          tickets = Ticket.where(query, *bind_params).joins(tables).limit(limit)
          return [ticket_count, tickets]
        end

        access_condition = Ticket.access_condition(current_user, access)
        ticket_count = Ticket.where(access_condition).where(query, *bind_params).joins(tables).count
        tickets = Ticket.where(access_condition).where(query, *bind_params).joins(tables).limit(limit)

        return [ticket_count, tickets]
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.error e.inspect
        Rails.logger.error e.backtrace
        raise ActiveRecord::Rollback
      end
    end
    []
  end

=begin

generate condition query to search for tickets based on condition

  query_condition, bind_condition, tables = selector2sql(params[:condition], current_user)

condition example

  {
    'ticket.title' => {
      operator: 'contains', # contains not
      value: 'some value',
    },
    'ticket.state_id' => {
      operator: 'is',
      value: [1,2,5]
    },
    'ticket.created_at' => {
      operator: 'after (absolute)', # after,before
      value: '2015-10-17T06:00:00.000Z',
    },
    'ticket.created_at' => {
      operator: 'within next (relative)', # before,within,in,after
      range: 'day', # minute|hour|day|month|year
      value: '25',
    },
    'ticket.owner_id' => {
      operator: 'is', # is not
      pre_condition: 'current_user.id',
    },
    'ticket.owner_id' => {
      operator: 'is', # is not
      pre_condition: 'specific',
      value: 4711,
    },
    'ticket.escalation_at' => {
      operator: 'is not', # not
      value: nil,
    },
    'ticket.tags' => {
      operator: 'contains all', # contains all|contains one|contains all not|contains one not
      value: 'tag1, tag2',
    },
  }

=end

  def self.selector2sql(selectors, current_user = nil)
    current_user_id = UserInfo.current_user_id
    if current_user
      current_user_id = current_user.id
    end
    return if !selectors

    # remember query and bind params
    query = ''
    bind_params = []
    like = Rails.application.config.db_like

    # get tables to join
    tables = ''
    selectors.each { |attribute, selector|
      selector = attribute.split(/\./)
      next if !selector[1]
      next if selector[0] == 'ticket'
      next if tables.include?(selector[0])
      if query != ''
        query += ' AND '
      end
      if selector[0] == 'customer'
        tables += ', users customers'
        query += 'tickets.customer_id = customers.id'
      elsif selector[0] == 'organization'
        tables += ', organizations'
        query += 'tickets.organization_id = organizations.id'
      elsif selector[0] == 'owner'
        tables += ', users owners'
        query += 'tickets.owner_id = owners.id'
      elsif selector[0] == 'article'
        tables += ', ticket_articles articles'
        query += 'tickets.id = articles.ticket_id'
      else
        raise "invalid selector #{attribute.inspect}->#{selector.inspect}"
      end
    }

    # add conditions
    selectors.each { |attribute, selector_raw|

      # validation
      raise "Invalid selector #{selector_raw.inspect}" if !selector_raw
      raise "Invalid selector #{selector_raw.inspect}" if !selector_raw.respond_to?(:key?)
      selector = selector_raw.stringify_keys
      raise "Invalid selector, operator missing #{selector.inspect}" if !selector['operator']

      # validate value / allow empty but only if pre_condition exists and is not specific
      if !selector.key?('value') || ((selector['value'].class == String || selector['value'].class == Array) && (selector['value'].respond_to?(:empty?) && selector['value'].empty?))
        return nil if selector['pre_condition'].nil?
        return nil if selector['pre_condition'].respond_to?(:empty?) && selector['pre_condition'].empty?
        return nil if selector['pre_condition'] == 'specific'
      end

      # validate pre_condition values
      return nil if selector['pre_condition'] && selector['pre_condition'] !~ /^(not_set|current_user\.|specific)/

      # get attributes
      attributes = attribute.split(/\./)
      attribute = "#{attributes[0]}s.#{attributes[1]}"

      # magic selectors
      if attributes[0] == 'ticket' && attributes[1] == 'out_of_office_replacement_id'
        attribute = "#{attributes[0]}s.owner_id"
      end

      if attributes[0] == 'ticket' && attributes[1] == 'tags'
        selector['value'] = selector['value'].split(/,/).collect(&:strip)
      end

      if query != ''
        query += ' AND '
      end

      if selector['operator'] == 'is'
        if selector['pre_condition'] == 'not_set'
          if attributes[1] =~ /^(created_by|updated_by|owner|customer|user)_id/
            query += "#{attribute} IN (?)"
            bind_params.push 1
          else
            query += "#{attribute} IS NULL"
          end
        elsif selector['pre_condition'] == 'current_user.id'
          raise "Use current_user.id in selector, but no current_user is set #{selector.inspect}" if !current_user_id
          if attributes[1] == 'out_of_office_replacement_id'
            query += "#{attribute} IN (?)"
            bind_params.push User.find(current_user_id).out_of_office_agent_of.pluck(:id)
          else
            query += "#{attribute} IN (?)"
            bind_params.push current_user_id
          end
        elsif selector['pre_condition'] == 'current_user.organization_id'
          raise "Use current_user.id in selector, but no current_user is set #{selector.inspect}" if !current_user_id
          query += "#{attribute} IN (?)"
          user = User.lookup(id: current_user_id)
          bind_params.push user.organization_id
        else
          # rubocop:disable Style/IfInsideElse
          if selector['value'].nil?
            query += "#{attribute} IS NULL"
          else
            if attributes[1] == 'out_of_office_replacement_id'
              query += "#{attribute} IN (?)"
              bind_params.push User.find(selector['value']).out_of_office_agent_of.pluck(:id)
            else
              query += "#{attribute} IN (?)"
              bind_params.push selector['value']
            end
          end
          # rubocop:enable Style/IfInsideElse
        end
      elsif selector['operator'] == 'is not'
        if selector['pre_condition'] == 'not_set'
          if attributes[1] =~ /^(created_by|updated_by|owner|customer|user)_id/
            query += "#{attribute} NOT IN (?)"
            bind_params.push 1
          else
            query += "#{attribute} IS NOT NULL"
          end
        elsif selector['pre_condition'] == 'current_user.id'
          if attributes[1] == 'out_of_office_replacement_id'
            query += "#{attribute} NOT IN (?)"
            bind_params.push User.find(current_user_id).out_of_office_agent_of.pluck(:id)
          else
            query += "#{attribute} NOT IN (?)"
            bind_params.push current_user_id
          end
        elsif selector['pre_condition'] == 'current_user.organization_id'
          query += "#{attribute} NOT IN (?)"
          user = User.lookup(id: current_user_id)
          bind_params.push user.organization_id
        else
          # rubocop:disable Style/IfInsideElse
          if selector['value'].nil?
            query += "#{attribute} IS NOT NULL"
          else
            if attributes[1] == 'out_of_office_replacement_id'
              query += "#{attribute} NOT IN (?)"
              bind_params.push User.find(selector['value']).out_of_office_agent_of.pluck(:id)
            else
              query += "#{attribute} NOT IN (?)"
              bind_params.push selector['value']
            end
          end
          # rubocop:enable Style/IfInsideElse
        end
      elsif selector['operator'] == 'contains'
        query += "#{attribute} #{like} (?)"
        value = "%#{selector['value']}%"
        bind_params.push value
      elsif selector['operator'] == 'contains not'
        query += "#{attribute} NOT #{like} (?)"
        value = "%#{selector['value']}%"
        bind_params.push value
      elsif selector['operator'] == 'contains all' && attributes[0] == 'ticket' && attributes[1] == 'tags'
        query += "? = (
                                              SELECT
                                                COUNT(*)
                                              FROM
                                                tag_objects,
                                                tag_items,
                                                tags
                                              WHERE
                                                tickets.id = tags.o_id AND
                                                tag_objects.id = tags.tag_object_id AND
                                                tag_objects.name = 'Ticket' AND
                                                tag_items.id = tags.tag_item_id AND
                                                tag_items.name IN (?)
                                            )"
        bind_params.push selector['value'].count
        bind_params.push selector['value']
      elsif selector['operator'] == 'contains one' && attributes[0] == 'ticket' && attributes[1] == 'tags'
        query += "1 <= (
                          SELECT
                            COUNT(*)
                          FROM
                            tag_objects,
                            tag_items,
                            tags
                          WHERE
                            tickets.id = tags.o_id AND
                            tag_objects.id = tags.tag_object_id AND
                            tag_objects.name = 'Ticket' AND
                            tag_items.id = tags.tag_item_id AND
                            tag_items.name IN (?)
                        )"
        bind_params.push selector['value']
      elsif selector['operator'] == 'contains all not' && attributes[0] == 'ticket' && attributes[1] == 'tags'
        query += "0 = (
                        SELECT
                          COUNT(*)
                        FROM
                          tag_objects,
                          tag_items,
                          tags
                        WHERE
                          tickets.id = tags.o_id AND
                          tag_objects.id = tags.tag_object_id AND
                          tag_objects.name = 'Ticket' AND
                          tag_items.id = tags.tag_item_id AND
                          tag_items.name IN (?)
                      )"
        bind_params.push selector['value']
      elsif selector['operator'] == 'contains one not' && attributes[0] == 'ticket' && attributes[1] == 'tags'
        query += "(
                    SELECT
                      COUNT(*)
                    FROM
                      tag_objects,
                      tag_items,
                      tags
                    WHERE
                      tickets.id = tags.o_id AND
                      tag_objects.id = tags.tag_object_id AND
                      tag_objects.name = 'Ticket' AND
                      tag_items.id = tags.tag_item_id AND
                      tag_items.name IN (?)
                  ) BETWEEN ? AND ?"
        bind_params.push selector['value']
        bind_params.push selector['value'].count - 1
        bind_params.push selector['value'].count
      elsif selector['operator'] == 'before (absolute)'
        query += "#{attribute} <= ?"
        bind_params.push selector['value']
      elsif selector['operator'] == 'after (absolute)'
        query += "#{attribute} >= ?"
        bind_params.push selector['value']
      elsif selector['operator'] == 'within last (relative)'
        query += "#{attribute} >= ?"
        time = nil
        if selector['range'] == 'minute'
          time = Time.zone.now - selector['value'].to_i.minutes
        elsif selector['range'] == 'hour'
          time = Time.zone.now - selector['value'].to_i.hours
        elsif selector['range'] == 'day'
          time = Time.zone.now - selector['value'].to_i.days
        elsif selector['range'] == 'month'
          time = Time.zone.now - selector['value'].to_i.months
        elsif selector['range'] == 'year'
          time = Time.zone.now - selector['value'].to_i.years
        else
          raise "Unknown selector attributes '#{selector.inspect}'"
        end
        bind_params.push time
      elsif selector['operator'] == 'within next (relative)'
        query += "#{attribute} <= ?"
        time = nil
        if selector['range'] == 'minute'
          time = Time.zone.now + selector['value'].to_i.minutes
        elsif selector['range'] == 'hour'
          time = Time.zone.now + selector['value'].to_i.hours
        elsif selector['range'] == 'day'
          time = Time.zone.now + selector['value'].to_i.days
        elsif selector['range'] == 'month'
          time = Time.zone.now + selector['value'].to_i.months
        elsif selector['range'] == 'year'
          time = Time.zone.now + selector['value'].to_i.years
        else
          raise "Unknown selector attributes '#{selector.inspect}'"
        end
        bind_params.push time
      elsif selector['operator'] == 'before (relative)'
        query += "#{attribute} <= ?"
        time = nil
        if selector['range'] == 'minute'
          time = Time.zone.now - selector['value'].to_i.minutes
        elsif selector['range'] == 'hour'
          time = Time.zone.now - selector['value'].to_i.hours
        elsif selector['range'] == 'day'
          time = Time.zone.now - selector['value'].to_i.days
        elsif selector['range'] == 'month'
          time = Time.zone.now - selector['value'].to_i.months
        elsif selector['range'] == 'year'
          time = Time.zone.now - selector['value'].to_i.years
        else
          raise "Unknown selector attributes '#{selector.inspect}'"
        end
        bind_params.push time
      elsif selector['operator'] == 'after (relative)'
        query += "#{attribute} >= ?"
        time = nil
        if selector['range'] == 'minute'
          time = Time.zone.now + selector['value'].to_i.minutes
        elsif selector['range'] == 'hour'
          time = Time.zone.now + selector['value'].to_i.hours
        elsif selector['range'] == 'day'
          time = Time.zone.now + selector['value'].to_i.days
        elsif selector['range'] == 'month'
          time = Time.zone.now + selector['value'].to_i.months
        elsif selector['range'] == 'year'
          time = Time.zone.now + selector['value'].to_i.years
        else
          raise "Unknown selector attributes '#{selector.inspect}'"
        end
        bind_params.push time
      else
        raise "Invalid operator '#{selector['operator']}' for '#{selector['value'].inspect}'"
      end
    }

    [query, bind_params, tables]
  end

=begin

perform changes on ticket

  ticket.perform_changes({}, 'trigger', item, current_user_id)

=end

  def perform_changes(perform, perform_origin, item = nil, current_user_id = nil)
    logger.debug "Perform #{perform_origin} #{perform.inspect} on Ticket.find(#{id})"

    # if the configuration contains the deletion of the ticket then
    # we skip all other ticket changes because they does not matter
    if perform['ticket.action'].present? && perform['ticket.action']['value'] == 'delete'
      perform.each do |key, _value|
        (object_name, attribute) = key.split('.', 2)
        next if object_name != 'ticket'
        next if attribute == 'action'

        perform.delete(key)
      end
    end

    changed = false
    perform.each do |key, value|
      (object_name, attribute) = key.split('.', 2)
      raise "Unable to update object #{object_name}.#{attribute}, only can update tickets and send notifications!" if object_name != 'ticket' && object_name != 'notification'

      # send notification
      if object_name == 'notification'

        # value['recipient'] was a string in the past (single-select) so we convert it to array if needed
        value_recipient = value['recipient']
        if !value_recipient.is_a?(Array)
          value_recipient = [value_recipient]
        end

        recipients_raw = []
        value_recipient.each { |recipient|
          if recipient == 'article_last_sender'
            if item && item[:article_id]
              article = Ticket::Article.lookup(id: item[:article_id])
              if article.reply_to.present?
                recipients_raw.push(article.reply_to)
              elsif article.from.present?
                recipients_raw.push(article.from)
              elsif article.origin_by_id
                email = User.lookup(id: article.origin_by_id).email
                recipients_raw.push(email)
              elsif article.created_by_id
                email = User.lookup(id: article.created_by_id).email
                recipients_raw.push(email)
              end
            end
          elsif recipient == 'ticket_customer'
            email = User.lookup(id: customer_id).email
            recipients_raw.push(email)
          elsif recipient == 'ticket_owner'
            email = User.lookup(id: owner_id).email
            recipients_raw.push(email)
          elsif recipient == 'ticket_agents'
            User.group_access(group_id, 'full').sort_by(&:login).each do |user|
              recipients_raw.push(user.email)
            end
          else
            logger.error "Unknown email notification recipient '#{recipient}'"
            next
          end
        }

        recipients_checked = []
        recipients_raw.each { |recipient_email|

          skip_user = false
          users = User.where(email: recipient_email)
          users.each { |user|
            next if user.preferences[:mail_delivery_failed] != true
            next if !user.preferences[:mail_delivery_failed_data]
            till_blocked = ((user.preferences[:mail_delivery_failed_data] - Time.zone.now - 60.days) / 60 / 60 / 24).round
            next if till_blocked.positive?
            logger.info "Send no trigger based notification to #{recipient_email} because email is marked as mail_delivery_failed for #{till_blocked} days"
            skip_user = true
            break
          }
          next if skip_user

          # send notifications only to email adresses
          next if !recipient_email
          next if recipient_email !~ /@/

          # check if address is valid
          begin
            recipient_email = Mail::Address.new(recipient_email).address
          rescue
            next # because unable to parse
          end

          # do not sent notifications to this recipients
          send_no_auto_response_reg_exp = Setting.get('send_no_auto_response_reg_exp')
          begin
            next if recipient_email =~ /#{send_no_auto_response_reg_exp}/i
          rescue => e
            logger.error "ERROR: Invalid regex '#{send_no_auto_response_reg_exp}' in setting send_no_auto_response_reg_exp"
            logger.error 'ERROR: ' + e.inspect
            next if recipient_email =~ /(mailer-daemon|postmaster|abuse|root|noreply|noreply.+?|no-reply|no-reply.+?)@.+?/i
          end

          # check if notification should be send because of customer emails
          if item && item[:article_id]
            article = Ticket::Article.lookup(id: item[:article_id])
            if article && article.preferences['is-auto-response'] == true && article.from && article.from =~ /#{Regexp.quote(recipient_email)}/i
              logger.info "Send no trigger based notification to #{recipient_email} because of auto response tagged incoming email"
              next
            end
          end

          # loop protection / check if maximal count of trigger mail has reached
          map = {
            10 => 10,
            30 => 15,
            60 => 25,
            180 => 50,
            600 => 100,
          }
          skip = false
          map.each { |minutes, count|
            already_sent = Ticket::Article.where(
              ticket_id: id,
              sender: Ticket::Article::Sender.find_by(name: 'System'),
              type: Ticket::Article::Type.find_by(name: 'email'),
            ).where("ticket_articles.created_at > ? AND ticket_articles.to LIKE '%#{recipient_email.strip}%'", Time.zone.now - minutes.minutes).count
            next if already_sent < count
            logger.info "Send no trigger based notification to #{recipient_email} because already sent #{count} for this ticket within last #{minutes} minutes (loop protection)"
            skip = true
            break
          }
          next if skip
          map = {
            10 => 30,
            30 => 60,
            60 => 120,
            180 => 240,
            600 => 360,
          }
          skip = false
          map.each { |minutes, count|
            already_sent = Ticket::Article.where(
              sender: Ticket::Article::Sender.find_by(name: 'System'),
              type: Ticket::Article::Type.find_by(name: 'email'),
            ).where("ticket_articles.created_at > ? AND ticket_articles.to LIKE '%#{recipient_email.strip}%'", Time.zone.now - minutes.minutes).count
            next if already_sent < count
            logger.info "Send no trigger based notification to #{recipient_email} because already sent #{count} in total within last #{minutes} minutes (loop protection)"
            skip = true
            break
          }
          next if skip

          email = recipient_email.downcase.strip
          next if recipients_checked.include?(email)
          recipients_checked.push(email)
        }

        next if recipients_checked.blank?
        recipient_string = recipients_checked.join(', ')

        group = self.group
        next if !group
        email_address = group.email_address
        if !email_address
          logger.info "Unable to send trigger based notification to #{recipient_string} because no email address is set for group '#{group.name}'"
          next
        end

        if !email_address.channel_id
          logger.info "Unable to send trigger based notification to #{recipient_string} because no channel is set for email address '#{email_address.email}' (id: #{email_address.id})"
          next
        end

        objects = {
          ticket: self,
          article: articles.last,
        }

        # get subject
        subject = NotificationFactory::Mailer.template(
          templateInline: value['subject'],
          locale: 'en-en',
          objects: objects,
          quote: false,
        )
        subject = subject_build(subject)

        body = NotificationFactory::Mailer.template(
          templateInline: value['body'],
          locale: 'en-en',
          objects: objects,
          quote: true,
        )

        Ticket::Article.create(
          ticket_id: id,
          to: recipient_string,
          subject: subject,
          content_type: 'text/html',
          body: body,
          internal: false,
          sender: Ticket::Article::Sender.find_by(name: 'System'),
          type: Ticket::Article::Type.find_by(name: 'email'),
          preferences: {
            perform_origin: perform_origin,
          },
          updated_by_id: 1,
          created_by_id: 1,
        )
        next
      end

      # update tags
      if key == 'ticket.tags'
        next if value['value'].blank?
        tags = value['value'].split(/,/)
        if value['operator'] == 'add'
          tags.each { |tag|
            tag_add(tag)
          }
        elsif value['operator'] == 'remove'
          tags.each { |tag|
            tag_remove(tag)
          }
        else
          logger.error "Unknown #{attribute} operator #{value['operator']}"
        end
        next
      end

      # delete ticket
      if key == 'ticket.action'
        next if value['value'].blank?
        next if value['value'] != 'delete'

        destroy

        next
      end

      # lookup pre_condition
      if value['pre_condition']
        if value['pre_condition'] =~ /^not_set/
          value['value'] = 1
        elsif value['pre_condition'] =~ /^current_user\./
          raise 'Unable to use current_user, got no current_user_id for ticket.perform_changes' if !current_user_id
          value['value'] = current_user_id
        end
      end

      # update ticket
      next if self[attribute].to_s == value['value'].to_s
      changed = true

      self[attribute] = value['value']
      logger.debug "set #{object_name}.#{attribute} = #{value['value'].inspect}"
    end
    return if !changed
    save
  end

=begin

get all email references headers of a ticket, to exclude some, parse it as array into method

  references = ticket.get_references

result

  ['message-id-1234', 'message-id-5678']

ignore references header(s)

  references = ticket.get_references(['message-id-5678'])

result

  ['message-id-1234']

=end

  def get_references(ignore = [])
    references = []
    Ticket::Article.select('in_reply_to, message_id').where(ticket_id: id).each { |article|
      if !article.in_reply_to.empty?
        references.push article.in_reply_to
      end
      next if !article.message_id
      next if article.message_id.empty?
      references.push article.message_id
    }
    ignore.each { |item|
      references.delete(item)
    }
    references
  end

=begin

get all articles of a ticket in correct order (overwrite active record default method)

  artilces = ticket.articles

result

  [article1, articl2]

=end

  def articles
    Ticket::Article.where(ticket_id: id).order(:created_at, :id)
  end

  def history_get(fulldata = false)
    list = History.list(self.class.name, self['id'], 'Ticket::Article')
    return list if !fulldata

    # get related objects
    assets = {}
    list.each { |item|
      record = Kernel.const_get(item['object']).find(item['o_id'])
      assets = record.assets(assets)

      if item['related_object']
        record = Kernel.const_get(item['related_object']).find( item['related_o_id'])
        assets = record.assets(assets)
      end
    }
    {
      history: list,
      assets: assets,
    }
  end

  private

  def check_generate
    return true if number
    self.number = Ticket::Number.generate
    true
  end

  def check_title
    return true if !title
    title.gsub!(/\s|\t|\r/, ' ')
    true
  end

  def check_defaults
    if !owner_id
      self.owner_id = 1
    end
    return true if !customer_id
    customer = User.find_by(id: customer_id)
    return true if !customer
    return true if organization_id == customer.organization_id
    self.organization_id = customer.organization_id
    true
  end

  def reset_pending_time

    # ignore if no state has changed
    return true if !changes_to_save['state_id']

    # ignore if new state is blank and
    # let handle ActiveRecord the error
    return if state_id.blank?

    # check if new state isn't pending*
    current_state      = Ticket::State.lookup(id: state_id)
    current_state_type = Ticket::StateType.lookup(id: current_state.state_type_id)

    # in case, set pending_time to nil
    return true if current_state_type.name =~ /^pending/i
    self.pending_time = nil
    true
  end

  def check_escalation_update
    escalation_calculation
    true
  end

  def set_default_state
    return true if state_id
    default_ticket_state = Ticket::State.find_by(default_create: true)
    return true if !default_ticket_state
    self.state_id = default_ticket_state.id
    true
  end

  def set_default_priority
    return true if priority_id
    default_ticket_priority = Ticket::Priority.find_by(default_create: true)
    return true if !default_ticket_priority
    self.priority_id = default_ticket_priority.id
    true
  end
end
