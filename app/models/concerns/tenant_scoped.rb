module TenantScoped
  extend ActiveSupport::Concern

  included do
    belongs_to :organization
  end

  class_methods do
    # Organization roots are resolved by membership, a token capability, or a trusted job.
    # Tenant rows themselves always enter through this relation, including UUID lookups.
    def for(scope)
      organization = scope&.organization
      raise ApiError.not_found unless organization&.persisted?

      where(organization_id: organization.id)
    end
  end
end
