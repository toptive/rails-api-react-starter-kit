module Api
  module V1
    module Admin
      class AuditEventsController < BaseController
        def index
          authorize AuditEvent
          render_collection(AuditEvent.admin_list(search_query), serializer: AuditEventSerializer)
        end
      end
    end
  end
end
