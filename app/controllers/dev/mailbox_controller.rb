module Dev
  class MailboxController < ApplicationController
    skip_before_action :require_json_body

    def show
      skip_authorization
      render_data(TestMailbox.messages, serializer: MailboxMessageSerializer)
    end

    def create
      skip_authorization
      TestMailbox.clear
      head :no_content
    end
  end
end
