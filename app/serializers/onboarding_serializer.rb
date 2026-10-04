class OnboardingSerializer
  include ApplicationSerializer

  typelize organization_name: :string, required: :boolean
  hash_attributes :organization_name, :required
end
