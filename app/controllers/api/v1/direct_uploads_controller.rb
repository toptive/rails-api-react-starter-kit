module Api
  module V1
    class DirectUploadsController < BaseController
      rate_limit to: 60, within: 1.minute, store: RATE_LIMIT_STORE, with: :render_rate_limited

      def create
        authorize Uploads
        attributes = params.permit(:filename, :content_type, :byte_size, :kind).to_h.symbolize_keys
        render_data(Uploads.presign(current_scope, attributes), serializer: DirectUploadSerializer, status: :created)
      end
    end
  end
end
