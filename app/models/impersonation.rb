class Impersonation < ApplicationRecord
  belongs_to :admin, class_name: "User", optional: true
  belongs_to :target_user, class_name: "User", optional: true
  validates :reason, presence: true, length: { minimum: 5, maximum: 255 }

  def self.start!(scope, target_id, attributes, request)
    User::Input.validate!(attributes, string_fields: [ :reason ], required: [ :reason ])
    transaction do
      scope.user.lock!
      scope.session.lock!
      raise ApiError.not_found unless scope.session.live? && scope.session.superadmin?

      target = User.lock.find(target_id)
      raise ApiError.forbidden if target.role == "superadmin" || target.id == scope.user.id

      impersonation = create!(admin: scope.user, target_user: target, reason: attributes[:reason])
      token = SecureRandom.urlsafe_base64(32)
      session = Session.create!(user: target, token_hash: Digest::SHA256.digest(token),
        expires_at: 8.hours.from_now, authenticated_at: Time.current, sudo_until: nil,
        impersonator_user: scope.user, impersonator_session: scope.session, impersonation: impersonation,
        ip_address: request.remote_ip, user_agent: request.user_agent&.slice(0, 255), last_used_at: Time.current)
      Session.scope_for(session)
      Audit.record("impersonation.started", scope: scope, subject: target,
        metadata: { reason: impersonation.reason, impersonationId: impersonation.id }, request: request)
      { token: token, expires_at: session.expires_at, sudo_until: nil, user: target,
        impersonator: scope.user, new_account: false, can_manage: session.can_manage? }
    end
  end
end
