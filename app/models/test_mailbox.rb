# Shared filesystem delivery lets short-lived fixture runners and the API see the same mail.
class TestMailbox
  def self.directory
    raise ApiError.not_found unless Rails.env.test? && ENV["E2E"] == "1"

    Rails.root.join("tmp", "mailbox", ENV.fetch("E2E_PGDATABASE"))
  end

  def self.deliver(mail)
    FileUtils.mkdir_p(directory)
    payload = { to: mail.to, text_body: mail.text_part&.body&.decoded || mail.body.decoded,
      html_body: mail.html_part&.body&.decoded.to_s }
    temporary = directory.join("#{SecureRandom.uuid}.tmp")
    File.write(temporary, JSON.generate(payload))
    File.rename(temporary, temporary.sub_ext(".json"))
  end

  def self.messages = directory.glob("*.json").sort_by { |path| path.mtime }.reverse.map { |path| JSON.parse(path.read).symbolize_keys }
  def self.clear = FileUtils.rm_f(directory.glob("*.json"))
end
