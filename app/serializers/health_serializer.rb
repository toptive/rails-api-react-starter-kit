class HealthSerializer
  include ApplicationSerializer

  typelize status: '"ok"'
  hash_attributes :status
end
