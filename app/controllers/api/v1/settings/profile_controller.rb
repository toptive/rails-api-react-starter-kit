module Api
  module V1
    module Settings
      class ProfileController < BaseController
        def update
          authorize current_user
          render_data(current_user.update_profile!(cast_string_attributes(:name, :locale)), serializer: UserSerializer)
        end
      end
    end
  end
end
