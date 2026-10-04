module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # Browser bearer sessions do not authorize WebSocket connections.
    def connect
      reject_unauthorized_connection
    end
  end
end
