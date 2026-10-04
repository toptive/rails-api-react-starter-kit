class UserToken < ApplicationRecord
  LIFETIMES = { "magic_link" => 15.minutes, "confirm" => 15.minutes, "reset_password" => 15.minutes }.freeze
  belongs_to :user

  def self.issue_for(user, context: "magic_link", sent_to: user.email)
    lifetime = context.start_with?("change_email:") ? 7.days : LIFETIMES.fetch(context)
    token = SecureRandom.urlsafe_base64(32)
    create!(user: user, token_hash: Digest::SHA256.digest(token), context: context,
      sent_to: sent_to, expires_at: Time.current + lifetime)
    token
  end

  def self.magic_link(token)
    raise ApiError.unprocessable(:magic_link_invalid) unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9_-]{43}\z/)

    row = find_by(token_hash: Digest::SHA256.digest(token), context: "magic_link")
    raise ApiError.unprocessable(:magic_link_invalid) unless row && row.expires_at > Time.current && row.sent_to == row.user.email

    row
  end

  def self.peek(token)
    row = magic_link(token)
    { email: row.sent_to, confirmed: row.user.confirmed_at.present? }
  end

  def self.consume_magic_link!(token, expected_user: nil)
    transaction do
      row = magic_link(token)
      user = row.user
      # Lock the user first to serialize consumption of different confirmation links.
      user.with_lock do
        row.reload
        raise ApiError.unprocessable(:magic_link_invalid) unless row.expires_at > Time.current && row.sent_to == user.email
        raise ApiError.unprocessable(:magic_link_invalid) if expected_user && expected_user.id != user.id

        new_account = user.confirmed_at.nil?
        user.update!(confirmed_at: Time.current) if new_account
        row.destroy!
        user.user_tokens.where(context: [ "magic_link", "confirm" ]).delete_all if new_account
        [ user, new_account ]
      end
    end
  rescue ActiveRecord::RecordNotFound
    raise ApiError.unprocessable(:magic_link_invalid)
  end
end
