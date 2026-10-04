require "timeout"

class Health
  def self.check
    Timeout.timeout(2) { ActiveRecord::Base.connection_pool.with_connection { |connection| connection.select_value("SELECT 1") } }
    { body: "ok", status: :ok }
  rescue ActiveRecord::ActiveRecordError, PG::Error, SocketError, Timeout::Error
    { body: "database unavailable", status: :service_unavailable }
  end
end
