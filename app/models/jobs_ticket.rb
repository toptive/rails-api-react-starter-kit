class JobsTicket < ApplicationRecord
  belongs_to :session

  def self.consume!(id)
    ticket = find_by(id: id)
    raise ApiError.not_found unless ticket

    ticket.with_lock do
      raise ApiError.not_found if ticket.consumed_at || ticket.expires_at <= Time.current
      raise ApiError.not_found unless ticket.session.live? && ticket.session.superadmin?

      ticket.update!(consumed_at: Time.current)
      ticket.session
    end
  end

  def self.purge_expired = where("expires_at < ?", Time.current).delete_all
end
