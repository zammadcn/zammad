#class ActionDispatch::Routing::RouteSet
class ActionDispatch::Routing::Mapper
  def match_channel(api_path, scope, params = nil)
    scope api_path do
      resources "channels_#{scope}", except: %w[new edit show] do
        member do
          post :disable, :enable
        end

        params&.each do |(route_scope, config)|
          send(route_scope) do
            config.each do |method, actions|
              actions.each do |action|
                send(:map_method, method, [action])
              end
            end
          end
        end
      end
    end
  end
end

Zammad::Application.routes.draw do
  match_channel Rails.configuration.api_path, :sms, collection: { post: [:test] }
end
