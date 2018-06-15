class Observer::Ticket::Article::ApplicationCommunicateJob
  def initialize(id)
    @article_id = id
  end

  def max_attempts
    4
  end

  def reschedule_at(current_time, attempts)
    if Rails.env.production?
      return current_time + attempts * 120.seconds
    end
    current_time + 5.seconds
  end

  private

  # set retry count
  def bump_retry_count(article)
    if !article.preferences['delivery_retry']
      article.preferences['delivery_retry'] = 0
    end
    article.preferences['delivery_retry'] += 1
  end

  # log successful delivery
  def log_success(article)
    article.preferences['delivery_status_message'] = nil
    article.preferences['delivery_status'] = 'success'
    article.preferences['delivery_status_date'] = Time.zone.now
    article.save!
  end

  def log_error(local_record, message)
    local_record.preferences['delivery_status'] = 'fail'
    local_record.preferences['delivery_status_message'] = message
    local_record.preferences['delivery_status_date'] = Time.zone.now
    local_record.save
    Rails.logger.error message

    if local_record.preferences['delivery_retry'] >= max_attempts
      Ticket::Article.create(
        ticket_id: local_record.ticket_id,
        content_type: 'text/plain',
        body: "#{log_error_prefix}: #{message}",
        internal: true,
        sender: Ticket::Article::Sender.find_by(name: 'System'),
        type: Ticket::Article::Type.find_by(name: 'note'),
        preferences: {
          delivery_article_id_related: local_record.id,
          delivery_message: true,
        },
        updated_by_id: 1,
        created_by_id: 1,
      )
    end

    raise message
  end

  def log_history(article, ticket, history_type, recipient_list)
    return if recipient_list.empty?

    History.add(
      o_id: article.id,
      history_type: history_type,
      history_object: 'Ticket::Article',
      related_o_id: ticket.id,
      related_history_object: 'Ticket',
      value_from: article.subject,
      value_to: recipient_list,
      created_by_id: article.created_by_id,
    )
  end

  def log_error_prefix
    'Unable to communicate'
  end
end
