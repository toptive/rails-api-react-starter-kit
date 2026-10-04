class Subscription < ApplicationRecord
  include TenantScoped

  CLOSED_STATUSES = %w[canceled incomplete_expired].freeze
  validates :status, presence: true
  validates :livemode, inclusion: { in: [ true, false ] }

  def self.open?(scope)
    self.for(scope).where.not(status: CLOSED_STATUSES).exists?
  end
end
