module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # No socket sessions until the authentication domain issues cable tickets.
    def connect
      reject_unauthorized_connection
    end
  end
end
