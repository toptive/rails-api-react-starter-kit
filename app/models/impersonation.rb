class Impersonation < ApplicationRecord
  belongs_to :admin, class_name: "User", optional: true
  belongs_to :target_user, class_name: "User", optional: true
end
