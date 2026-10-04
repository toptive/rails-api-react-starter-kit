# Global webhook inbox. organization_id is an untrusted hint, not tenant authority.
class BillingEvent < ApplicationRecord
  self.inheritance_column = nil
end
