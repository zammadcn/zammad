class Observer::Ticket::Article::CommunicateSms::BackgroundJob < Observer::Ticket::Article::ApplicationCommunicateJob
  def perform
    article = Ticket::Article.find(@article_id)

    bump_retry_count(article)

    ticket = Ticket.lookup(id: article.ticket_id)
    log_error(article, "Can't find article.preferences for Article.find(#{article.id})") if !article.preferences
    log_error(article, "Can't find article.preferences['sms_recipients'] for Article.find(#{article.id})") if !article.preferences['sms_recipients']
    channel = Channel.lookup(id: ticket.preferences['channel_id'])
    log_error(article, "No such channel id #{ticket.preferences['channel_id']}") if !channel
    #log_error(article, "Channel.find(#{channel.id}) has no twilio api credentials!") if channel.options[:auth][:token].blank? || channel.options[:auth][:account_sid].blank?

    begin
      driver = channel.driver_instance.new channel.options
      article.preferences['sms_recipients'].each do |recipient|
        result = driver.send(recipient, article.body.first(160))
      end
    rescue => e
      log_error(article, e.message)
      return
    end

    log_success(article)

    recipient_list = article.to

    log_history(article, ticket, 'sms', recipient_list)
  end

  def log_error_prefix
    'Unable to send sms message'
  end
end
