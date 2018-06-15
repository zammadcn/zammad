FactoryBot.define do
  factory :trigger do
    name 'Trigger'
    condition({
                'ticket.action': {
                  operator: 'is',
                  value: 'create'
                }
              })
    active true
    updated_by_id 1
    created_by_id 1
  end
end
