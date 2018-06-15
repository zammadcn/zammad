class Observer::Ticket::Article::CommunicateSms < ActiveRecord::Observer
  observe 'ticket::_article'

  def after_create(record)
    return if Setting.import?
    return if !Ticket::Article::Sender.not_customer?(record)
    return if !Ticket::Article::Type.named?(record, 'sms')

    Delayed::Job.enqueue(Observer::Ticket::Article::CommunicateSms::BackgroundJob.new(record.id))
  end
end
