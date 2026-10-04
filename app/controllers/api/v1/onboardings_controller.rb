module Api
  module V1
    class OnboardingsController < BaseController
      def show
        authorize current_scope.organization, :onboarding?
        render_data(Organization.onboarding(current_scope), serializer: OnboardingSerializer)
      end

      def update
        authorize current_scope.organization, :onboarding?
        attributes = cast_string_attributes(:name)
        render_data(Organization.update_current!(current_scope, attributes, request, onboarding: true), serializer: OrganizationSerializer)
      end
    end
  end
end
