# name: discourse-aws
# about: Push notifications via AWS SNS
# version: 0.1
# authors: pmusaraj, neogucky
# originally developed by pmusaraj

after_initialize do
  if SiteSetting.aws_push_enabled
    ONESIGNALAPI = 'https://onesignal.com/api/v1/notifications'

   Rails.logger.info("after init aws")

    DiscourseEvent.on(:post_notification_alert) do |user, payload|

      if SiteSetting.aws_app_id.nil? || SiteSetting.aws_app_id.empty?
          Rails.logger.warn('OneSignal App ID is missing')
          return
      end
      if SiteSetting.aws_rest_api_key.nil? || SiteSetting.aws_rest_api_key.empty?
          Rails.logger.warn('OneSignal REST API Key is missing')
          return
      end

      clients = user.user_api_keys
          .where("('push' = ANY(scopes) OR 'notifications' = ANY(scopes)) AND push_url IS NOT NULL AND position(push_url in ?) > 0 AND revoked_at IS NULL",
                    ONESIGNALAPI)
          .pluck(:client_id, :push_url)

      if clients.length > 0
        Jobs.enqueue(:aws_pushnotification, clients: clients, payload: payload, username: user.username)
      end

    end

    module ::Jobs
      class AwsPushnotification < Jobs::Base
        def execute(args)
          payload = args["payload"]
          Rails.logger.info("maybe aws key?  #{args['clients']}.")

          params = {
            "app_id" => SiteSetting.aws_app_id,
            "contents" => {"en" => "#{payload[:username]}: #{payload[:excerpt]}"},
            "headings" => {"en" => payload[:topic_title]},
            "data" => {"discourse_url" => payload[:post_url]},
            "ios_badgeType" => "Increase",
            "ios_badgeCount" => "1",
            "filters" => [
                {"field": "tag", "key": "username", "relation": "=", "value": args["username"]},
              ]
          }

          uri = URI.parse(ONESIGNALAPI)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true if uri.scheme == 'https'

          request = Net::HTTP::Post.new(uri.path,
              'Content-Type'  => 'application/json;charset=utf-8',
              'Authorization' => "Basic #{SiteSetting.aws_rest_api_key}")
          request.body = params.as_json.to_json
          response = http.request(request)

          case response
          when Net::HTTPSuccess then
            Rails.logger.info("Push notification sent via OneSignal to #{args['username']}.")
          else
            Rails.logger.error("OneSignal error")
            Rails.logger.error("#{request.to_yaml}")
            Rails.logger.error("#{response.to_yaml}")

          end
        end
      end
    end
  end
end
